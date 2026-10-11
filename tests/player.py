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
                if allow_unavailable and reply["error"] == "property unavailable": return None
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
        deadline=time.monotonic()+6
        last,consecutive=None,0
        while time.monotonic() < deadline:
            dimensions=self.dimensions()
            consecutive=consecutive+1 if dimensions==last else 0
            if consecutive >= 6:
                return dimensions
            last=dimensions
            time.sleep(.1)
        raise AssertionError("Window resize did not settle")

    def mouse(self, x, y, click=False, button=0):
        _, _, scale = self.dimensions()
        self.command("mouse", round(x*scale), round(y*scale), *([button, "single"] if click else []))
        time.sleep(.12)

    def menu_is_open(self):
        """The forced Escape binding exists only while a skin menu is open."""
        return any(binding.get("cmd", "").endswith("script-binding mpvtube/menu-escape")
                   for binding in self.get("input-bindings"))

    def selected_row(self, count, expected):
        """Check the one visible checkmark recorded by the integration-only drawing wrapper."""
        _,h,_=self.dimensions()
        capacity=max(1,int((h-100-57-16)/48))
        height=57+min(count,capacity)*48+16
        offset=min(max(0,expected-capacity),max(0,count-capacity))
        y=h-62-height+57+8+(expected-offset-.5)*48
        deadline=time.monotonic()+2
        checks=[]
        while time.monotonic()<deadline:
            checks=self.get("user-data/mpvtube-test-checks")
            if len(checks)==1 and abs(checks[0]["y"]-y)<.5: return
            time.sleep(.02)
        raise AssertionError(f"Expected the checkmark on row {expected}, got {checks}")

    def menu(self, page, count, row=None, header=True):
        self.command("script-message-to", "mpvtube", "menu", page)
        # YouTube-style page slides suppress pointer actions for 250 ms.
        time.sleep(.28)
        w, h, _ = self.dimensions()
        header_height=57 if header else 0
        cap = max(1, int((h-100-header_height-16)/48))
        height = header_height + min(count, cap)*48+16
        # All panels share a right edge; this click anchor also fits narrow choice menus.
        x, y = w-212, h-62-height
        if row is not None:
            offset=min(max(0,row-cap),max(0,count-cap))
            if offset:
                self.mouse(x+100,y+header_height+8+24)
                for _ in range(offset): self.command("keypress","WHEEL_DOWN")
                time.sleep(.1)
            self.mouse(x+100, y+header_height+8+(row-offset-.5)*48, True)
        else:
            self.mouse(x+100,y+header_height+8+24)
        return x, y

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
        w,h,_=self.dimensions()
        capacity=max(1,int((h-100-57-16)/48))
        offset=max(0,2-capacity)
        for _ in range(offset): self.command("keypress","WHEEL_DOWN")
        slider_x,row_y,slider_width=self.speed_slider()
        self.mouse(slider_x+(value-.25)/1.75*slider_width,row_y,True)
        self.near("speed",value)

    def speed_slider(self):
        """Geometry after speed() has scrolled the slider into view."""
        w,h,_=self.dimensions()
        capacity=max(1,int((h-100-57-16)/48))
        offset=max(0,2-capacity)
        width=min(320,w-24)
        height=57+min(3,capacity)*48+16
        slider_x=w-width-12+64
        row_y=h-62-height+57+8+(2-offset-.5)*48
        return slider_x,row_y,width-128

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
