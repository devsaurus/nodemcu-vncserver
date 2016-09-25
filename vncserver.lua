-- ***************************************************************************
-- VNC server framework for Lua on NodeMCU.
--
-- An implementaion of the RFB protocol:
--    http://vncdotool.readthedocs.io/en/latest/rfbproto.html
--
-- Inspired by pylotron, https://github.com/cnlohr/pylotron
--
-- ---------------------------------------------------------------------------
--
-- Copyright (c) 2016, Arnim Laeuger
--
-- Redistribution and use in source, with or without modification, are
-- permitted provided the above copyright notice and these terms are retained.
--
-- ---------------------------------------------------------------------------
--

local M, module = {}, ...
_G[module] = M

local srv_conn
local srv_state
local send_buf


local disp_width, disp_height

local cb_key, cb_pointer, cb_fbupdate, cb_disconnection, cb_datasent

local function set_defaults()
  send_buf = nil
  srv_state = ""
  srv_conn = nil
end

local function buf_sent( conn )
  if #send_buf > 0 then
    conn:send( table.remove( send_buf, 1 ), buf_sent )
  else
    send_buf = nil
    if cb_datasent then cb_datasent() end
  end
end

local function event_disconn( conn )
   if cb_disconnection then cb_disconnection() end
   set_defaults()
end

local function num_bits_used( val )
  local num = 0
  while val > 0 do
    num = num + 1
    val = bit.rshift( val, 1 )
  end
  return num
end

local function event_data( conn, data )
  if srv_state == "connected" then
    -- server announces its protocol version
    M.queue_msg( "RFB 003.003\n" )
    srv_state = "wait_clientproto"

  elseif srv_state == "wait_clientproto" then
    -- client selects protocol version
    -- just omit data

    -- send security handshake
    -- no security
    M.queue_msg( struct.pack( ">I4", 1 ) )
    srv_state = "wait_clientinit"

  elseif srv_state == "wait_clientinit" then
    -- get sharing info
    -- just omit data

    -- send server init
    M.queue_msg( struct.pack( ">I2I2BBBBI2I2I2BBBbbbI4s", disp_width, disp_height, 8, 3, 0, 1, 1, 1, 1, 0, 1, 2, 0, 0, 0, 4, "ESP" ) )
    srv_state = "wait_clientmsg"

  elseif srv_state == "wait_clientmsg" then
    local cmd = struct.unpack( "B", data )

    if cmd == 0 then
      -- client requests different pixel type

      local bpp, dep, be, tc = struct.unpack( "BBBB", data, 2 + 3 )
      M.red_max, M.green_max, M.blue_max, M.red_shift, M.green_shift, M.blue_shift = struct.unpack( ">I2I2I2BBB", data, 2 + 7 )
      -- determine how many bits are used for the color components
      M.red_len = num_bits_used( M.red_max )
      M.green_len = num_bits_used( M.green_max )
      M.blue_len = num_bits_used( M.blue_max )

      M.white = bit.bor( bit.lshift( M.red_max, M.red_shift),
                         bit.lshift( M.green_max, M.green_shift),
                         bit.lshift( M.blue_max, M.blue_shift) )

      local endian_format
      if be > 0 then
        endian_format = ">"
      else
        endian_format = "<"
      end
      if bpp == 8 then
        M.bpp_format = "B"
      elseif bpp == 16 then
        M.bpp_format = endian_format.."I2"
      elseif bpp == 24 or bpp == 32 then
        M.bpp_format = endian_format.."I4"
      end

    elseif cmd == 2 then
      -- encodings

    elseif cmd == 3 then
      -- client requests update
      if cb_fbupdate then
        cb_fbupdate()
      end

    elseif cmd == 4 then
      -- key press event
      if cb_key then
        local down, _, key = struct.unpack( ">BI2I4", data, 2 )
        cb_key( key, down > 0 )
      end

    elseif cmd == 5 then
      -- pointer event
      if cb_pointer then
        cb_pointer( struct.unpack( ">BI2I2", data, 2 ) )
      end

    elseif cmd == 6 then
      -- client cut text

    end

  end
end


-- Exported API --------------------------------------------------------------
--
-- Exported variables
--
M.bpp_format = nil
M.red_max = 0
M.green_max = 0
M.blue_max = 0
M.red_shift = 0
M.green_shift = 0
M.blue_shift = 0
M.red_len = 0
M.green_len = 0
M.blue_len = 0

--
-- Exported functions
--
-- queue_msg( data )
-- Queue "data" for sending to the client.
-- The send processing is asynchronous, thus expect this function to return before the
-- payload has actually be sent to the client.
function M.queue_msg( data )
  if srv_conn == nil then return end

  if send_buf == nil then
    send_buf = {}
    srv_conn:send( data, buf_sent )
  else
    if #send_buf > 0 and (data:len() + send_buf[#send_buf]:len()) < 1400 then
      -- marshall small data strings
      send_buf[#send_buf] = send_buf[#send_buf] .. data
    else
      -- add payload to buffer
      send_buf[#send_buf + 1] = data
    end
  end
end

-- rre_rectangle( x, y, w, h, num_subrects, bg )
-- Starts a rectangle in RRE format composed out of 'num_subrects' sub-rectangles.
function M.rre_rectangle( x, y, w, h, num_subrects, bg )
  M.queue_msg( struct.pack( ">I2I2I2I2i4I4"..M.bpp_format, x, y, w, h, 2,
                            num_subrects, bg ) )
end

-- rre_subrectangle( x, y, w, h, fg )
-- Append an RRE subrectangle to a previously started rectangle.
function M.rre_subrectangle( x, y, w, h, fg )
  M.queue_msg( struct.pack( M.bpp_format..">I2I2I2I2", fg, x, y, w, h ) )
end

-- update_fb( num_rects )
-- Start a framebuffer update consisting of 'num_rects' rectangles to follow.
function M.update_fb( num_rects )
  M.queue_msg( struct.pack( ">BBI2", 0, 0, num_rects ) )
end

-- on( event, cb )
-- Register callback function, or unregister if cb is omitted.
function M.on( event, cb )
  if event == "key" then
    cb_key = cb
  elseif event == "pointer" then
    cb_pointer = cb
  elseif event == "fb_update" then
    cb_fbupdate = cb
  elseif event == "disconnection" then
    cb_disconnection = cb
  elseif event == "data_sent" then
    cb_datasent = cb
  else
    error( "unknown event" )
  end
end

-- start( conn, width, height )
-- Start server on connection "conn" with display size "width" and "height".
function M.start( conn, width, height )
  srv_conn = conn
  srv_state = "connected"

  disp_width = width
  disp_height = height

  conn:on( "receive", event_data )
  conn:on( "disconnection", event_disconn )

  event_data( conn, nil )
end

return M
