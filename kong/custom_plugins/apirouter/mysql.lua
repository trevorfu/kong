local config = require "kong.custom_plugins.apirouter.config"
local resty_mysql = require "resty.mysql"

local mysql = {}

--[[
    先从连接池取连接,如果没有再建立连接.
    返回:
        false,出错信息.
        true,数据库连接
--]]
function mysql:get_connect()
  if ngx.ctx[mysql] then
    return true, ngx.ctx[mysql]
  end

  local client, errmsg = resty_mysql:new()
  if not client then
    return false, "[mysql] socket failed: " .. (errmsg or "nil")
  end

  client:set_timeout(10000)  --10秒

  local options = {
    host = config.DBHOST,
    port = config.DBPORT,
    user = config.DBUSER,
    password = config.DBPASSWORD,
    database = config.DBNAME
  }

  local result, errmsg, errno, sqlstate = client:connect(options)
  if not result then
    return false, "[mysql] connect failed: " .. (errmsg or "nil") .. ", errno: " .. (errno or "nil") ..
            ", sql_state: " .. (sqlstate or "nil")
  end

  local query = "SET NAMES " .. config.DEFAULT_CHARSET
  local result, errmsg, errno, sqlstate = client:query(query)
  if not result then
    return false, "[mysql] query failed: " .. (errmsg or "nil") .. ", errno: " .. (errno or "nil") ..
            ", sql_state: " .. (sqlstate or "nil")
  end

  ngx.ctx[mysql] = client
  return true, ngx.ctx[mysql]
end

--[[
    把连接返回到连接池
    用set_keepalive代替close() 将开启连接池特性,可以为每个nginx工作进程，指定连接最大空闲时间，和连接池最大连接数
 --]]
function mysql:close()
  if ngx.ctx[mysql] then
    ngx.ctx[mysql]:set_keepalive(60000, 1000)
    ngx.ctx[mysql] = nil
  end
end

--[[
    查询
    有结果数据集时返回结果数据集
    无数据数据集时返回查询影响
    返回:
        false,出错信息,sqlstate结构.
        true,结果集,sqlstate结构.
--]]
function mysql:query(sql)
  local ret, client = self:get_connect()
  if not ret then
    return false, client, nil
  end

  local result, errmsg, errno, sqlstate = client:query(sql)
  self:close()

  if type(result) ~= "table" then
    local errmsg = "[mysql] query failed," .. " errno:" .. errno .. " errmsg:" .. errmsg .. " sqlstate:" .. sqlstate
    return false, errmsg, sqlstate
  end

  return true, result, sqlstate
end

return mysql