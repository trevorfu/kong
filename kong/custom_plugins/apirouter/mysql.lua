local resty_mysql = require "resty.mysql"

local mysql = {}

--[[
    先从连接池取连接,如果没有再建立连接.
    返回:
        false,出错信息.
        true,数据库连接
--]]
function mysql:get_connect(conf)
  if ngx.ctx[mysql] then
    return true, ngx.ctx[mysql]
  end

  local client, err = resty_mysql:new()
  if not client then
    return false, "[mysql] socket failed: " .. (err or "nil")
  end

  client:set_timeout(conf.mysql_timeout)

  local options = {
    host = conf.mysql_host,
    port = conf.mysql_port,
    user = conf.mysql_username,
    password = conf.mysql_password,
    database = conf.mysql_dbname
  }

  local ok, err, errno, sqlstate = client:connect(options)
  if not ok then
    return false, "[mysql] connect failed: " .. (err or "nil") .. ", errno: " .. (errno or "nil") ..
            ", sql_state: " .. (sqlstate or "nil")
  end

  local query = "SET NAMES " .. conf.mysql_charset
  local ok, err, errno, sqlstate = client:query(query)
  if not ok then
    return false, "[mysql] query failed: " .. (err or "nil") .. ", errno: " .. (errno or "nil") ..
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
function mysql:query(conf, sql)
  local ok, client = self:get_connect(conf)
  if not ok then
    return false, client, nil
  end

  local ok, err, errno, sqlstate = client:query(sql)
  self:close()

  if type(ok) ~= "table" then
    local err = "[mysql] query failed," .. " errno:" .. errno .. " errmsg:" .. err .. " sqlstate:" .. sqlstate
    return false, err, sqlstate
  end

  return true, ok, sqlstate
end

return mysql