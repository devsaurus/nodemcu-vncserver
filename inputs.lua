
vncsrv = require("vncserver")


-- ***************************************************************************
-- VNC client message callbacks
-- 
function cb_disconnect()
  print( "client disconnected" )
end

-- Process key events
function cb_key( key, down )
  local action
  if down then
    action = "pressed"
  else
    action = "released"
  end
  if key >= 10 and key <= 127 then
    print( string.format( "key '%c' %s", key, action ) )
  else
    print( string.format( "key '0x%04x' %s", key, action ) )
  end
end

-- Process pointer events
function cb_pointer( button_mask, x, y )
  local buttons = ""

  print( string.format( "pointer at x %d / y %d", x, y ) )

  if bit.band( button_mask, 2^0 ) > 0 then
    buttons = "left "
  end
  if bit.band( button_mask, 2^1 ) > 0 then
    buttons = buttons.."middle "
  end
  if bit.band( button_mask, 2^2 ) > 0 then
    buttons = buttons.."right "
  end
  if bit.band( button_mask, 2^3 ) > 0 then
    buttons = buttons.."up "
  end
  if bit.band( button_mask, 2^4 ) > 0 then
    buttons = buttons.."down "
  end
  if bit.band( button_mask, 2^5 ) > 0 then
    buttons = buttons.."left "
  end
  if bit.band( button_mask, 2^6 ) > 0 then
    buttons = buttons.."right"
  end
  if buttons:len() > 0 then
    print( string.format( "button: %s", buttons ) )
  end
end


-- ***************************************************************************
-- Initialization part
--

-- Configure VNC server
vncsrv.on( "disconnection", cb_disconnect )
vncsrv.on( "key", cb_key )
vncsrv.on( "pointer", cb_pointer )

-- Set up TCP server
srv = net.createServer( net.TCP, 120 )
srv:listen( 5900,
            function( conn )
              -- start VNC server with connected socket
              vncsrv.start( conn, 128, 64 )
            end
)
