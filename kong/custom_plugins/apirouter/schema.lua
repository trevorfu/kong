local utils = require "kong.tools.utils"

local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end

return {
  no_consumer = true,
  fields = {
    key_names = { required = true, type = "string", default = "user-key" },
    -- anonymous = { type = "string", default = "", func = check_user },
    -- hide_credentials = { type = "boolean", default = true },
    -- redis config 
    redis_host = { required = true, type = "string", default = "120.132.2.210" },
    redis_port = { required = true, type = "number", default = 6379 },
    redis_password = { type = "string" },
    redis_timeout = { type = "number", default = 5000 },
    redis_database = { type = "number", default = 0 },
    -- mysql config
    mysql_host = { required = true, type = "string", default = "120.132.2.210" },
    mysql_port = { required = true, type = "number", default = 3306 },
    mysql_username = { required = true, type = "string", default = "wancloud" },
    mysql_password = { required = true, type = "string", default = "wancloud" },
    mysql_dbname = { required = true, type = "string", default = "wancloud" },
    mysql_timeout = { type = "number", default = 5000 },
    mysql_charset = { type = "string", default = "utf8" },
    -- limit_by = { type = "string", enum = { "token", "ip", "api"}, default = "token" },
    limit_times = { type = "number", default = 2000 } -- ,
    -- limit_period = { type = "string", enum = { "second", "minute", "hour", "day", "month", "year"}, default = "day" }
  }
}