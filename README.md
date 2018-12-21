# nodemcu-vncserver
A VNC server framework for Lua on [NodeMCU](https://github.com/nodemcu/nodemcu-firmware). It implements a basic subset of the [RFB protocol](http://vncdotool.readthedocs.io/en/latest/rfbproto.html) and enables Lua scripts to send graphics via TCP connection to a VNC client on PC or smartphone.
It was inspired by [pylotron](https://github.com/cnlohr/pylotron) which demonstrates the simplicity of graphical interaction between an embedded system and a smart client via VNC.

Modules required to be compiled into the firmware:
- `net`
- `bit`
- `struct`
- `u8g2`

## Setting up the server
The vnc server operates on a [NodeMCU socket instance](http://nodemcu.readthedocs.io/en/dev/en/modules/net/#netsocket-module) and has to be created by the user script.which has to be prepared upfront by the user script:

```lua
require("vncserver").createServer(5900, width, height,
  function( srv )

  end
)
```

The `createServer()` function expects 4 mandatory parameters:
- `port` to listen at
- `width` of the announced display
- `height` of the announced display
- `user_init` user init function

The user init function is called when a client connected to the server. It should be used to prepare the new session and set up callback hooks.

All protocol sequences are subsequently handled by the vncserver module.

## Hooks for client events
Once the server exchanged all required info with the client, it stands by and waits for messages from the client. It will delegate these to the user script via callbacks. Callback functions for the following events can be registered within the user init function:
- `srv.cb_fbupdate` client sent a [FramebufferUpdateRequest](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#framebufferupdaterequest)
- `srv.cb_disconnection` client disconnected
- `srv.cb_key` client sent a [KeyEvent](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#keyevent)
- `srv.cb_pointer` client sent a [PointerEvent](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#pointerevent)
- `srv.cb_datasent` all queued data was sent to the client

```lua
srv.cb_disconnection = function( srv )
  print( "client disconnected" )
end
srv.cb_fbupdate = function( srv )
  print( "framebuffer update requested" )
end
srv.cb_key = function( srv, key, down )
  -- 'key' contains the keysym
  -- 'down' is true for key pressed and false for key released
  print( "key event received" )
end
srv.cb_pointer = function( srv, button_mask, x, y )
  -- 'button_mask' contains the state of 7 pointer buttons
  -- 'x' and 'y' are the current pointer coordinates
  print( "pointer event received" )
end
```

## Sending graphics to the client
Whenever the client requests a framebuffer update, the server needs to send a [FramebufferUpdate](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#framebufferupdate) message containing a list of rectangles. Note that vncserver only supports [RRE encoding](http://vncdotool.readthedocs.io/en/latest/rfbproto.html#rre-encoding) at the moment.

A rectangle tells the client which area of the display is affected and what is the background color of this region:

`srv:rre_rectangle( base_x, base_y, width, height, num_subrectangles, background )`

The following sub-rectangles (if any) define the regions with different colors. They are specified relative to the surrounding rectangle:

`srv:rre_subrectangle( rel_x, rel_y, width, height, color )`

Example from `rectangles.lua`:

```lua
function draw_rectangles()
  -- FramebufferUpdate message indicating that 1 rectangle description follows:
  srv:update_fb( 1 )
  -- Next is the rectangle in RRE encoding, 4 sub-rectangles will follow:
  srv:rre_rectangle( 0, 0, 128, 128, 4, 0 ) 
  -- The sub-rectangles:
  srv:rre_subrectangle( 10, 10, 30, 10, red )
  srv:rre_subrectangle( 50, 20, 20, 40, green )
  srv:rre_subrectangle( 80, 80, 40, 40, blue )
  srv:rre_subrectangle( 60, 50, 30, 50, yellow )
end
```

For more advanced graphics there's an integration with the u8g2 library, see `u8g2_vnc.lua`.

### Pixel color
Clients can request a variety of pixel encoding formats. They boil down to the definition of how many values for the red, green, and blue components are available and where they are located inside the transmitted pixel info.

The server stores the client's definitions during the initial handshaking process and provides them as variables to the user script:
- `srv.red_max` maximum red value
- `srv.green_max` maximum green value
- `srv.blue_max` maximum blue value
- `srv.red_shift` shift for red to final slot
- `srv.green_shift` shift for green to final slot
- `srv.blue_shift` shift for blue to final slot
- `srv.red_len` red value bit length
- `srv.green_len` green value bit length
- `srv.blue_len` blue value bit length

User code needs to adapt its color encoding to these parameters or the client will not be able interpret the colors correctly. See `rectangles.lua` for an example.
