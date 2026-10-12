"""Small JSON IPC client shared by native MPV checks."""
import json
import socket
import time

class Player:
    def __init__(self, ipc):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(8)
        self.sock.connect(str(ipc))
        self.file = self.sock.makefile("r")
        self.serial = 0

    def command(self, *args, allow_unavailable=False):
        self.serial += 1
        self.sock.sendall((json.dumps({"command": args, "request_id": self.serial}) + "\n").encode())
        while True:
            line = self.file.readline()
            if not line:
                raise RuntimeError("MPV exited unexpectedly")
            reply = json.loads(line)
            if reply.get("request_id") == self.serial:
                if allow_unavailable and reply["error"] in ("property unavailable","property not found"): return None
                assert reply["error"] == "success", (args, reply)
                return reply.get("data")

    def get(self, property):
        return self.command("get_property", property)

    def optional(self, property):
        return self.command("get_property", property, allow_unavailable=True)

    def wait(self, property, expected, timeout=4):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            # A file change briefly removes properties before the next file exposes them.
            value = self.optional(property)
            if value == expected:
                return
            time.sleep(.04)
        raise AssertionError(f"{property}: expected {expected!r}, got {value!r}")

    def position(self, expected, tolerance=.3, timeout=4):
        self.near("time-pos",expected,tolerance,timeout)

    def near(self, property, expected, tolerance=.08, timeout=4):
        deadline=time.monotonic()+timeout
        while time.monotonic() < deadline:
            value=self.optional(property)
            if value is not None and abs(value-expected) < tolerance:
                return
            time.sleep(.05)
        raise AssertionError(f"{property}: expected {expected}, got {value}")

    def dimensions(self):
        # A VO can be configured before macOS has assigned its initial client size.
        deadline=time.monotonic()+4
        dimensions=self.get("osd-dimensions")
        while (not dimensions["w"] or not dimensions["h"]) and time.monotonic()<deadline:
            time.sleep(.05)
            dimensions=self.get("osd-dimensions")
        assert dimensions["w"] and dimensions["h"],"MPV window has no drawable size"
        w, h = dimensions["w"], dimensions["h"]
        scale = min(max(1, self.get("display-hidpi-scale")), w/300, h/180)
        return round(w/scale), round(h/scale), scale

    def settle(self):
        deadline=time.monotonic()+8
        # macOS can keep the old VO size briefly while entering its native fullscreen space.
        required=16 if self.optional("fullscreen") else 6
        last,consecutive=None,0
        while time.monotonic() < deadline:
            dimensions=self.dimensions()
            consecutive=consecutive+1 if dimensions==last else 0
            if consecutive >= required:
                return dimensions
            last=dimensions
            time.sleep(.1)
        raise AssertionError("Window resize did not settle")

    def mouse(self, x, y, click=False, button=0):
        _, _, scale = self.dimensions()
        self.command("mouse", round(x*scale), round(y*scale), *([button, "single"] if click else []))
        time.sleep(.12)

    def snapshot(self):
        token=str(self.serial+1)
        self.command("script-message-to","mpvtube","test-state",token)
        deadline=time.monotonic()+2
        while time.monotonic()<deadline:
            value=self.optional("user-data/mpvtube-test-state")
            if value and value["token"]==token: return value
            time.sleep(.01)
        raise AssertionError("Skin state snapshot unavailable")

    def wait_state(self, field, expected, timeout=3):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            state=self.snapshot()
            if state[field]==expected: return state
            time.sleep(.01)
        raise AssertionError(f"Skin {field}: expected {expected!r}, got {state[field]!r}")

    def control(self, name, click=True):
        hit=next(hit for hit in self.snapshot()["hits"] if hit["id"]==name)
        self.mouse(hit["x"]+hit["w"]/2,hit["y"]+hit["h"]/2,click)
        return hit

    def close_menu(self):
        self.command("keypress","BS")
        deadline=time.monotonic()+2
        while time.monotonic()<deadline:
            if not self.menu_is_open(): return
            time.sleep(.02)
        raise AssertionError("Menu/focus did not clear")

    def close_native(self):
        """Wait for MPV's console/select capture to release before sending playback keys."""
        def active():
            return any(binding.get("priority",-1)>=0 and "console/_console_text" in binding.get("cmd","")
                       for binding in self.get("input-bindings"))
        # IPC acknowledges a script action before the native dialog finishes opening.
        deadline=time.monotonic()+2
        while not active() and time.monotonic()<deadline:
            time.sleep(.01)
        assert active(),"Native console/select panel did not open"
        self.command("keypress","ESC")
        deadline=time.monotonic()+2
        while time.monotonic()<deadline:
            if not active(): return
            time.sleep(.01)
        raise AssertionError("Native console/select input did not release")

    def menu_is_open(self):
        """The routing section's Escape binding is active while a menu or control has focus."""
        return any(binding.get("priority",-1)>=0 and binding.get("cmd", "").endswith("script-binding mpvtube/menu-escape")
                   for binding in self.get("input-bindings"))

    def selected_row(self, count, expected):
        """Compare the drawn checkmark with the visible row from the actual layout."""
        deadline=time.monotonic()+2
        checks=[]
        while time.monotonic()<deadline:
            state=self.snapshot()
            hit=next((hit for hit in state["hits"] if hit.get("index")==expected),None)
            checks=self.get("user-data/mpvtube-test-checks")
            if hit and len(checks)==1 and abs(checks[0]["y"]-hit["y"]-hit["h"]/2)<.5: return
            time.sleep(.02)
        raise AssertionError(f"Expected the checkmark on row {expected}, got {checks}")

    def menu(self, page, count, row=None, header=True):
        """Open and target an index or label using shared geometry, with no animation wait."""
        previous=self.snapshot()["menu"]
        self.command("script-message-to","mpvtube","menu",page)
        state=self.wait_state("menu",False if previous==page else page)
        if state["menu"] is False: return 0,0
        panel=state["panel"]
        anchor_x=panel["x"]+panel["w"]/2
        anchor_y=panel["y"]+panel["header"]+panel["padding"]+panel["row_h"]/2
        if row is not None:
            self.menu_row(row)
        else:
            self.mouse(anchor_x,anchor_y)
        return panel["x"],panel["y"]

    def menu_row(self, row):
        """Reveal and click a row in an already open menu, including compact scrollable lists."""
        state=self.snapshot()
        panel=state["panel"]
        self.mouse(panel["x"]+panel["w"]/2,panel["y"]+panel["header"]+panel["padding"]+panel["row_h"]/2)
        if isinstance(row,str):
            row=next(i+1 for i,item in enumerate(state["rows"]) if item["label"]==row)
        for _ in range(len(state["rows"])+1):
            state=self.snapshot()
            hit=next((hit for hit in state["hits"] if hit.get("index")==row),None)
            if hit:
                self.mouse(hit["x"]+hit["w"]/2,hit["y"]+hit["h"]/2,True)
                return
            self.command("keypress","WHEEL_UP" if row<=state["panel"]["offset"] else "WHEEL_DOWN")
            time.sleep(.02)
        raise AssertionError(f"Menu row {row} is unreachable")

    def screenshot(self, path):
        time.sleep(.25)
        self.command("screenshot-to-file", str(path), "window")

    def frames(self, prefix, action, offsets):
        """Capture native transition frames without screenshot()'s settling delay."""
        start=time.monotonic()
        action()
        timings=[]
        for offset in offsets:
            time.sleep(max(0,start+offset-time.monotonic()))
            # JPEG avoids slow PNG encoding swallowing the rest of a short transition.
            path=prefix.with_name(f"{prefix.name}-{round(offset*1000)}ms.jpg")
            requested=time.monotonic()-start
            self.command("screenshot-to-file",str(path),"window")
            timings.append({"target_ms":round(offset*1000),"requested_ms":round(requested*1000)})
        prefix.with_suffix(".json").write_text(json.dumps(timings,indent=2)+"\n")

    def speed(self, value):
        self.menu("speed",3)
        for _ in range(3):
            if any(hit["id"]=="speed-slider" for hit in self.snapshot()["hits"]): break
            self.command("keypress","WHEEL_DOWN")
            time.sleep(.02)
        slider_x,row_y,slider_width=self.speed_slider()
        self.mouse(slider_x+(value-.25)/1.75*slider_width,row_y,True)
        self.near("speed",value)

    def speed_slider(self):
        hit=next(hit for hit in self.snapshot()["hits"] if hit["id"]=="speed-slider")
        return hit["x"],hit["y"]+hit["h"]/2,hit["w"]

    def speed_drag(self, values):
        """Check every intermediate rate while one mouse press remains held."""
        self.speed(values[0])
        slider_x,row_y,slider_width=self.speed_slider()
        paused=self.get("pause")
        self.mouse(slider_x+(values[0]-.25)/1.75*slider_width,row_y)
        self.command("keydown","MBTN_LEFT")
        # IPC replies precede Lua callbacks; let the press capture its gesture before moving.
        time.sleep(.04)
        for index,value in enumerate(values[1:]):
            # Vertical excursions and horizontal overshoot must not cancel the gesture.
            self.mouse(slider_x+(value-.25)/1.75*slider_width,8 if index%2 else row_y)
            self.near("speed",min(2,max(.25,value)),.025)
        self.command("keyup","MBTN_LEFT")
        # MPV dispatches script callbacks asynchronously; settle release before moving again.
        time.sleep(.12)
        expected=min(2,max(.25,values[-1]))
        self.mouse(slider_x,row_y)
        self.near("speed",expected,.025)
        self.wait("pause",paused)
