--[[

Copyright (C) 2021 zPonds <admin@shinenet.cn>
Copyright (C) 2020 KFERMercer <KFER.Mercer@gmail.com>
Copyright (C) 2020 [CTCGFW] Project OpenWRT

THIS IS FREE SOFTWARE, LICENSED UNDER GPLv3

]]--

local nixio = require "nixio"
local yaml = require "lyaml"

m = Map("nezha-agent-v1")
m.title	= translate("哪吒监控")
m.description = translate("哪吒监控Agent配置")

m:section(SimpleSection).template = "nezha-agent-v1/nezha-agent_status"

s = m:section(NamedSection, "config", "nezha-agent-v1", translate("配置"))
s.anonymous = true
s.addremove = false

local function read_yaml()
    local f = io.open("/etc/config/nz.yml", "r")
    if f then
        local content = f:read("*all")
        f:close()
        return yaml.load(content) or {}
    end
    return {}
end

local function write_yaml(data)
    local f = io.open("/etc/config/nz.yml", "w")
    if f then
        -- 使用lyaml.dump处理复杂类型（数组和对象）
        local yaml_content = yaml.dump({data})
        f:write(yaml_content)
        f:close()
        
        nixio.syslog("debug", "Writing to nz.yml: " .. yaml_content)
        
        return true
    end
    return false
end

local function read_other_yaml()
    local f = io.open("/usr/share/nezha/other.yml", "r")
    if f then
        local content = f:read("*all")
        f:close()
        return yaml.load(content) or {}
    end
    return {}
end

local function write_other_yaml(data)
    local f = io.open("/usr/share/nezha/other.yml", "w")
    if f then
        -- 使用lyaml.dump处理复杂类型（数组和对象）
        local yaml_content = yaml.dump({data})
        f:write(yaml_content)
        f:close()
        
        nixio.syslog("debug", "Writing to other.yml: " .. yaml_content)
        
        return true
    end
    return false
end

function m.on_commit(self)
    -- 从UCI配置中读取所有值
    local uci = require "luci.model.uci".cursor()
    local data = {
        -- 基本设置
        server = uci:get("nezha-agent-v1", "config", "server"),
        client_secret = uci:get("nezha-agent-v1", "config", "client_secret"),
        uuid = uci:get("nezha-agent-v1", "config", "uuid"),
        tls = uci:get("nezha-agent-v1", "config", "tls") == "1",
        insecure_tls = uci:get("nezha-agent-v1", "config", "insecure_tls") == "1",
        
        -- 高级设置
        debug = uci:get("nezha-agent-v1", "config", "debug") == "1",
        disable_auto_update = uci:get("nezha-agent-v1", "config", "disable_auto_update") == "1",
        disable_command_execute = uci:get("nezha-agent-v1", "config", "disable_command_execute") == "1",
        disable_force_update = uci:get("nezha-agent-v1", "config", "disable_force_update") == "1",
        disable_nat = uci:get("nezha-agent-v1", "config", "disable_nat") == "1",
        temperature = uci:get("nezha-agent-v1", "config", "temperature") == "1",
        skip_procs_count = uci:get("nezha-agent-v1", "config", "skip_procs_count") == "1",
        skip_connection_count = uci:get("nezha-agent-v1", "config", "skip_connection_count") == "1",
        report_delay = tonumber(uci:get("nezha-agent-v1", "config", "report_delay")) or 3,
        ip_report_period = tonumber(uci:get("nezha-agent-v1", "config", "ip_report_period")) or 1800
    }
    
    -- 读取other.yml中的默认配置
    local other_config = read_other_yaml() or {}
    
    -- 读取UCI中的其他配置项
    local uci_other_config = uci:get_all("nezha-agent-v1", "config") or {}
    
    -- 合并配置：UCI配置优先于other.yml默认值
    for key, value in pairs(other_config) do
        if uci_other_config[key] ~= nil then
            -- 根据配置类型转换值
            if type(value) == "boolean" then
                data[key] = uci_other_config[key] == "1"
            elseif type(value) == "number" then
                data[key] = tonumber(uci_other_config[key]) or value
            else
                data[key] = uci_other_config[key]
            end
        else
            data[key] = value
        end
    end

    -- 删除旧的 YAML 文件
    os.remove("/etc/config/nz.yml")
    nixio.syslog("debug", "Removed old nz.yml")

    -- 写入新配置
    local result = write_yaml(data)
    
    -- 如果写入成功，重启服务
    if result then
        nixio.syslog("debug", "Configuration saved, restarting nezha-agent")
        luci.sys.call("/etc/init.d/nezha-agent restart >/dev/null 2>&1")
    else
        nixio.syslog("err", "Failed to write configuration to nz.yml")
    end
end

-- 修改默认值的设置方式
local config = read_yaml()
local uci = require "luci.model.uci".cursor()

-- 基本设置
s:tab("basic", translate("基本设置"))

o = s:taboption("basic", Value, "server", translate("面板地址"))
o.description = translate("格式: 域名:端口 或 IP:端口")
o.default = uci:get("nezha-agent-v1", "config", "server") or ""
o.rmempty = false

o = s:taboption("basic", Value, "client_secret", translate("客户端密钥"))
o.description = translate("在面板配置页面获取")
o.default = uci:get("nezha-agent-v1", "config", "client_secret") or ""
o.rmempty = false

o = s:taboption("basic", Value, "uuid", translate("UUID"))
o.description = translate("自行生成")
o.default = uci:get("nezha-agent-v1", "config", "uuid") or ""
o.rmempty = false

o = s:taboption("basic", Flag, "tls", translate("启用 TLS"))
o.default = config.tls or false
o.rmempty = false

o = s:taboption("basic", Flag, "insecure_tls", translate("跳过 TLS 验证"))
o.default = config.insecure_tls or false
o.rmempty = false

-- 高级设置
s:tab("advanced", translate("高级设置"))

-- 其它设置
s:tab("other", translate("其它设置"))

o = s:taboption("advanced", Flag, "debug", translate("调试模式"))
o.default = config.debug or false

o = s:taboption("advanced", Flag, "disable_auto_update", translate("禁用自动更新"))
o.default = config.disable_auto_update or false

o = s:taboption("advanced", Flag, "disable_command_execute", translate("禁用命令执行"))
o.default = config.disable_command_execute or false

o = s:taboption("advanced", Flag, "disable_force_update", translate("禁用强制更新"))
o.default = config.disable_force_update or false

o = s:taboption("advanced", Flag, "disable_nat", translate("禁用 NAT 支持"))
o.default = config.disable_nat or false

o = s:taboption("advanced", Flag, "temperature", translate("启用温度监控"))
o.default = config.temperature or false

o = s:taboption("advanced", Flag, "skip_procs_count", translate("禁用进程数监控"))
o.default = config.skip_procs_count or false

o = s:taboption("advanced", Flag, "skip_connection_count", translate("禁用网络连接数监控"))
o.default = config.skip_connection_count or false

o = s:taboption("advanced", Value, "report_delay", translate("报告延迟(秒)"))
o.default = config.report_delay or 3
o.datatype = "uinteger"

o = s:taboption("advanced", Value, "ip_report_period", translate("IP报告周期(秒)"))
o.default = config.ip_report_period or 1800
o.datatype = "uinteger"

-- 动态生成其它设置表单字段
local other_config = read_other_yaml() or {}
local uci_cursor = require "luci.model.uci".cursor()

-- 配置项的中文翻译映射
local translation_map = {
    disable_send_query = translate("禁用发送查询"),
    gpu = translate("GPU监控"),
    use_gitee_to_upgrade = translate("使用Gitee进行升级"),
    use_ipv6_country_code = translate("使用IPv6国家代码"),
    self_update_period = translate("自动更新周期(秒)")
}

-- 动态生成表单字段
for key, default_value in pairs(other_config) do
    local translation = translation_map[key] or key
    local uci_value = uci_cursor:get("nezha-agent-v1", "config", key)
    
    -- 跳过数组和对象类型的配置项（仅通过配置文件修改）
    if type(default_value) ~= "table" then
        if type(default_value) == "boolean" then
            -- 布尔类型使用Flag组件
            local o = s:taboption("other", Flag, key, translation)
            o.default = (uci_value == "1") or default_value
        elseif type(default_value) == "number" then
            -- 数字类型使用Value组件
            local o = s:taboption("other", Value, key, translation)
            o.default = tonumber(uci_value) or default_value
            o.datatype = "uinteger"
        else
            -- 其他类型使用Value组件
            local o = s:taboption("other", Value, key, translation)
            o.default = uci_value or default_value
        end
    end
end

return m
