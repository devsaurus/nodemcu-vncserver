# nodemcu-vncserver
A VNC server framework for Lua on [NodeMCU](https://github.com/nodemcu/nodemcu-firmware). It implements a basic subset of the [RFB protocol](http://vncdotool.readthedocs.io/en/latest/rfbproto.html) and enables Lua scripts to send graphics via TCP connection to a VNC client on PC or smartphone.
It was inspired by [pylotron](https://github.com/cnlohr/pylotron) which demonstrates the simplicity of graphical interaction between an embedded system and a smart client via VNC.

Modules required to be compiled into the firmware:
- `net`
- `bit`
- `struct`
- `u8g` with fb_rle display for esp8266 firmware
- `u8g2` for esp32 firmware

## Setting up the server
The vnc server operates on a [NodeMCU socket instance](http://nodemcu.readthedocs.io/en/dev/en/modules/net/#netsocket-module) which has to be prepared upfront by the user script: Establish a TCP server listening on port 5900 and call the `start()` function when a client connects.

```lua
vncsrv = require("vncserver")

-- Set up TCP server
srv = net.createServer( net.TCP, 120 )
srv:listen( 5900,
            function( conn )
              -- start VNC server with connected socket
              vncsrv.start( conn, 128, 128 )
            end
)
```

All protocol sequences are subsequently handled by the vncserver module.

## Hooks for client events
Once the server exchanged all required info, it stands by and waits for messages from the client. It will delegate these to the user script via callbacks. Callback functions for the following events can be registered with `vncsrv.on()`
- `fb_update` client sent a [FramebufferUpdateRequest](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#framebufferupdaterequest)
- `disconnection` client disconnected
- `key` client sent a [KeyEvent](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#keyevent)
- `pointer` client sent a [PointerEvent](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#pointerevent)
- `data_sent` all queued data was sent to the client

```lua
vncsrv.on( "disconnection", function()
  print( "client disconnected" )
end )
vncsrv.on( "fb_update", function()
  print( "framebuffer update requested" )
end )
vncsrv.on( "key", function( key, down )
  -- 'key' contains the keysym
  -- 'down' is true for key pressed and false for key released
  print( "key event received" )
end )
vncsrv.on( "pointer", function( button_mask, x, y )
  -- 'button_mask' contains the state of 7 pointer buttons
  -- 'x' and 'y' are the current pointer coordinates
  print( "pointer event received" )
end )
```

## Sending graphics to the client
Whenever the client requests a framebuffer update, the server should send a [FramebufferUpdate](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#framebufferupdate) message containing a list of rectangles. Note that vncserver only supports [RRE encoding](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#rre-encoding) at the moment.

A rectangle tells the client which area of the display is affected and what is the background color of this region:

`vncsrv.rre_rectangle( base_x, base_y, width, height, num_subrectangles, background )`

The following sub-rectangles (if any) define the regions with different colors. They are specified relative to the surrounding rectangle:

`vncsrv.rre_subrectangle( rel_x, rel_y, width, height, color )`

Example from `rectangles.lua`:

```lua
function draw_rectangles()
  -- FramebufferUpdate message indicating that 1 rectangle description follows:
  vncsrv.update_fb( 1 )
  -- Next is the rectangle in RRE encoding, 4 sub-rectangles will follow:
  vncsrv.rre_rectangle( 0, 0, 128, 128, 4, 0 )
  -- The sub-rectangles:
  vncsrv.rre_subrectangle( 10, 10, 30, 10, red )
  vncsrv.rre_subrectangle( 50, 20, 20, 40, green )
  vncsrv.rre_subrectangle( 80, 80, 40, 40, blue )
  vncsrv.rre_subrectangle( 60, 50, 30, 50, yellow )
end
```

For more advanced graphics there's an integration with the u8g and u8g2 libraries.

On esp8266 add the virtual RLE framebuffer display into the firmware and render any u8g script on the VNC client (see `u8g_vnc.lua` for details):

```lua
disp = u8g.fb_rle( drv_cb, srv_width, srv_height )
```

For esp32 every u8g2 display driver is suitable to act as a virtual display:

```lua
disp = u8g2.ssd1306_128x64_noname( drv_cb )
```

### Pixel color
Clients can request a variety of pixel encoding formats. They boil down to the definition of how many values for the red, green, and blue components are available and where they are located inside the transmitted pixel info.

The server stores the client's definitions during the initial handshaking process and provides them as variables to the user script:
- `vncsrv.red_max` maximum red value
- `vncsrv.green_max` maximum green value
- `vncsrv.blue_max` maximum blue value
- `vncsrv.red_shift` shift for red to final slot
- `vncsrv.green_shift` shift for green to final slot
- `vncsrv.blue_shift` shift for blue to final slot
- `vncsrv.red_len` red value bit length
- `vncsrv.green_len` green value bit length
- `vncsrv.blue_len` blue value bit length

User code needs to adapt its color encoding to these parameters or the client will not be able interpret the colors correctly. See `rectangles.lua` for an example.
