# nodemcu-vncserver
A VNC server framework for Lua on [NodeMCU](https://github.com/nodemcu/nodemcu-firmware). It implements a basic subset of the [RFB protocol](http://vncdotool.readthedocs.io/en/latest/rfbproto.html) and enables Lua scripts send graphics via a TCP connection to a VNC client on the PC or smartphons.
It was inspired by [pylotron](https://github.com/cnlohr/pylotron) which demonstrates the simplicity of graphical interaction between an embedded system with a smart client via VNC.

Modules required to be compiled into the firmware:
- `net`
- `bit`
- `struct`

## Setting up the server
The vnc server operates on a [NodeMCU socket instance](http://nodemcu.readthedocs.io/en/dev/en/modules/net/#netsocket-module), thus the user script needs to prepare this socket. It does so by setting up a TCP server listening on port 5900 and calls the `start()` function when a client connects:

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

All protocol sequences are subsequently handled by the vncserver module alone.

## Hooks for client events
Once the server exchanged all required info, it stands by and waits for messages from the client. It will delegate these to the user script in form of callback. Callback functions for the following events can be registered with `vncsrv.on()`
- `fb_update` client sent a [FramebufferUpdateRequest](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#framebufferupdaterequest)
- `disconnection` client disconnected
- `key` client sent a [KeyEvent](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#keyevent)
- `pointer` client sent a [PointerEvent](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#pointerevent)

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

The following sub-rectangles (if any) define the regions with different colors. They are specified relative to the surrouding rectangle:

`vncsrv.rre_subrectangle( rel_x, rel_y, width, height, color )`

With specific values (see `rectangles.lua`):

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

### Pixel color
Clients can request a variety of pixel encoding formats. They boil down to the definition how many values for the red, green, and blue components are available and where they are located inside the encoded item.

The server provides this information from the initial handshaking process as variables to the user script:
- `vncsrv.red_max` maximum red value
- `vncsrv.green_max` maximum green value
- `vncsrv.blue_max` maximum blue value
- `vncsrv.red_shift` shift for red to final slot
- `vncsrv.green_shift` shift for green to final slot
- `vncsrv.blue_shift` shift for blue to final slot
- `vncsrv.red_len` red value bit length
- `vncsrv.green_len` green value bit length
- `vncsrv.blue_len` blue value bit length

The user script needs to adapt its color encoding to these parameters. Otherwise the client will not be able interpret the colors correctly. See `rectangles.lua` for an example.
