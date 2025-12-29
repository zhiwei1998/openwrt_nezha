--[[

Copyright (C) 2021 zPonds <admin@shinenet.cn>
Copyright (C) 2020 KFERMercer <KFER.Mercer@gmail.com>
Copyright (C) 2020 [CTCGFW] Project OpenWRT

THIS IS FREE SOFTWARE, LICENSED UNDER GPLv3

]]--

local nixio = require "nixio"
local yaml = require "lyaml"
local fs = require "nixio.fs"

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
        -- 定义配置项的输出顺序
        local ordered_keys = {
            "client_secret",
            "debug",
            "disable_auto_update",
            "disable_command_execute",
            "disable_force_update",
            "disable_nat",
            "disable_send_query",
            "gpu",
            "hard_drive_partition_allowlist",
            "insecure_tls",
            "ip_report_period",
            "nic_allowlist",
            "report_delay",
            "self_update_period",
            "server",
            "skip_connection_count",
            "skip_procs_count",
            "temperature",
            "tls",
            "use_gitee_to_upgrade",
            "use_ipv6_country_code",
            "uuid"
        }

        local yaml_content = ""

        -- 按照指定顺序生成YAML内容
        for _, key in ipairs(ordered_keys) do
            local value = data[key]
            if value ~= nil then
                if type(value) == "string" then
                    yaml_content = yaml_content .. key .. ": \"" .. value .. "\"\n"
                elseif type(value) == "boolean" then
                    yaml_content = yaml_content .. key .. ": " .. tostring(value) .. "\n"
                elseif type(value) == "number" then
                    yaml_content = yaml_content .. key .. ": " .. tostring(value) .. "\n"
                elseif type(value) == "table" then
                    -- 检查是否为空表
                    if next(value) ~= nil then
                        -- 检查是否为数组
                        local is_array = true
                        for k, _ in pairs(value) do
                            if type(k) ~= "number" then
                                is_array = false
                                break
                            end
                        end

                        if is_array then
                            yaml_content = yaml_content .. key .. ":\n"
                            for _, v in ipairs(value) do
                                yaml_content = yaml_content .. " - " .. v .. "\n"
                            end
                        else
                            yaml_content = yaml_content .. key .. ":\n"
                            for k, v in pairs(value) do
                                if type(v) == "boolean" then
                                    yaml_content = yaml_content .. "   " .. k .. ": " .. tostring(v) .. "\n"
                                elseif type(v) == "string" then
                                    yaml_content = yaml_content .. "   " .. k .. ": \"" .. v .. "\"\n"
                                else
                                    yaml_content = yaml_content .. "   " .. k .. ": " .. tostring(v) .. "\n"
                                end
                            end
                        end
                    end
                end
            end
        end

        f:write(yaml_content)
        f:close()
        
        nixio.syslog("debug", "Writing to nz.yml: " .. yaml_content)
        
        return true
    end
    return false
end

local function read_other_yaml()
    -- 硬编码的默认配置，替代从other.yml文件读取
    return {
        disable_send_query = false,
        gpu = false,
        use_gitee_to_upgrade = false,
        use_ipv6_country_code = false,
        self_update_period = 0,
        hard_drive_partition_allowlist = {},
        nic_allowlist = {}
    }
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
    
    -- 读取硬编码的默认配置
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
            elseif key == "hard_drive_partition_allowlist" and type(value) == "table" then
                -- 特殊处理硬盘分区白名单，将逗号分隔的字符串转换为数组
                local partitions_str = uci_other_config[key]
                if partitions_str and partitions_str ~= "" then
                    -- 分割字符串并去除空格
                    local partitions = {}
                    for partition in partitions_str:gmatch("([^,%s]+)") do
                        table.insert(partitions, partition)
                    end
                    if #partitions > 0 then
                        data[key] = partitions
                    end
                end
            elseif key == "nic_allowlist" and type(value) == "table" then
                -- 特殊处理网卡白名单，将逗号分隔的字符串转换为对象
                local nic_str = uci_other_config[key]
                if nic_str and nic_str ~= "" then
                    local nic_table = {}
                    -- 分割字符串并去除空格
                    for nic in nic_str:gmatch("([^,%s]+)") do
                        nic_table[nic] = true
                    end
                    if next(nic_table) ~= nil then
                        data[key] = nic_table
                    end
                end
            else
                data[key] = uci_other_config[key]
            end
        elseif key ~= "hard_drive_partition_allowlist" and key ~= "nic_allowlist" then
            -- 只有非硬盘分区白名单和非网卡白名单的配置项才使用默认值
            data[key] = value
        end
    end

    -- 删除旧的 YAML 文件
    os.remove("/etc/config/nz.yml")
    nixio.syslog("debug", "Removed old nz.yml")

    -- 写入新配置
    local result = write_yaml(data)
    
    -- 如果写入成功，根据启用状态控制服务
    if result then
        local enabled = uci:get("nezha-agent-v1", "config", "enabled") == "1"
        if enabled then
            nixio.syslog("debug", "Configuration saved, restarting nezha-agent")
            luci.sys.call("/etc/init.d/nezha-agent restart >/dev/null 2>&1")
        else
            nixio.syslog("debug", "Configuration saved, but nezha-agent is disabled, not restarting")
            luci.sys.call("/etc/init.d/nezha-agent stop >/dev/null 2>&1")
        end
    else
        nixio.syslog("err", "Failed to write configuration to nz.yml")
    end
end

-- 修改默认值的设置方式
local config = read_yaml()
local uci = require "luci.model.uci".cursor()

-- 基本设置
s:tab("basic", translate("基本设置"))

o = s:taboption("basic", Flag, "enabled", translate("已启用"))
o.rmempty = false
o.default = uci:get("nezha-agent-v1", "config", "enabled") or "1"

o = s:taboption("basic", ListValue, "config_mode", translate("配置文件"))
o:value("preset", translate("内置预设"))
o:value("custom", translate("自定义"))
o.default = uci:get("nezha-agent-v1", "config", "config_mode") or "preset"

-- 自定义配置文件编辑
o = s:taboption("basic", TextValue, "custom_config", translate("自定义配置编辑"))
o.template = "cbi/tvalue"
o.rows = 20
o.description = translate("编辑自定义配置文件内容")
o:depends("config_mode", "custom")
function o.cfgvalue(self, section)
    local custom_config_file = "/etc/config/nz_custom.yml"
    if fs.access(custom_config_file) then
        return fs.readfile(custom_config_file)
    end
    -- 如果自定义配置文件不存在，返回默认配置内容
    local default_config = io.open("/etc/config/nz.yml", "r")
    if default_config then
        local content = default_config:read("*all")
        default_config:close()
        return content
    end
    return ""
end
function o.write(self, section, value)
    local custom_config_file = "/etc/config/nz_custom.yml"
    value = value:gsub("\r\n?", "\n")
    fs.writefile(custom_config_file, value)
end

o = s:taboption("basic", Value, "server", translate("面板地址"))
o.description = translate("格式: 域名:端口 或 IP:端口")
o.default = uci:get("nezha-agent-v1", "config", "server") or ""
o.rmempty = false
o:depends("config_mode", "preset")

o = s:taboption("basic", Value, "client_secret", translate("客户端密钥"))
o.description = translate("在面板配置页面获取")
o.default = uci:get("nezha-agent-v1", "config", "client_secret") or ""
o.rmempty = false
o:depends("config_mode", "preset")

o = s:taboption("basic", Value, "uuid", translate("UUID"))
o.description = translate("自行生成")
o.default = uci:get("nezha-agent-v1", "config", "uuid") or ""
o.rmempty = false
o:depends("config_mode", "preset")

o = s:taboption("basic", Flag, "tls", translate("启用 TLS"))
o.default = config.tls or false
o.rmempty = false
o:depends("config_mode", "preset")

o = s:taboption("basic", Flag, "insecure_tls", translate("跳过 TLS 验证"))
o.default = config.insecure_tls or false
o.rmempty = false
o:depends("config_mode", "preset")

-- 高级设置
s:tab("advanced", translate("高级设置"))

-- 从UCI读取配置
local uci_cursor = require "luci.model.uci".cursor()

-- 配置项的中文翻译映射
local translation_map = {
    disable_send_query = translate("禁用发送查询"),
    gpu = translate("GPU监控"),
    use_gitee_to_upgrade = translate("使用Gitee进行升级"),
    use_ipv6_country_code = translate("使用IPv6国家代码"),
    self_update_period = translate("自动更新周期(秒)"),
    hard_drive_partition_allowlist = translate("需要监控的硬盘分区列表"),
    nic_allowlist = translate("需要监控的网卡")
}

-- 按照指定顺序添加所有高级设置选项

-- debug
o = s:taboption("advanced", Flag, "debug", translate("调试模式"))
o.default = (uci_cursor:get("nezha-agent-v1", "config", "debug") == "1") or false
o:depends("config_mode", "preset")

-- disable_auto_update
o = s:taboption("advanced", Flag, "disable_auto_update", translate("禁用自动更新"))
o.default = (uci_cursor:get("nezha-agent-v1", "config", "disable_auto_update") == "1") or false
o:depends("config_mode", "preset")

-- disable_command_execute
o = s:taboption("advanced", Flag, "disable_command_execute", translate("禁用命令执行"))
o.default = (uci_cursor:get("nezha-agent-v1", "config", "disable_command_execute") == "1") or false
o:depends("config_mode", "preset")

-- disable_force_update
o = s:taboption("advanced", Flag, "disable_force_update", translate("禁用强制更新"))
o.default = (uci_cursor:get("nezha-agent-v1", "config", "disable_force_update") == "1") or false
o:depends("config_mode", "preset")

-- disable_nat
o = s:taboption("advanced", Flag, "disable_nat", translate("禁用 NAT 支持"))
o.default = (uci_cursor:get("nezha-agent-v1", "config", "disable_nat") == "1") or false
o:depends("config_mode", "preset")

-- disable_send_query
o = s:taboption("advanced", Flag, "disable_send_query", translation_map["disable_send_query"])
o.default = (uci_cursor:get("nezha-agent-v1", "config", "disable_send_query") == "1") or false
o:depends("config_mode", "preset")

-- gpu
o = s:taboption("advanced", Flag, "gpu", translation_map["gpu"])
o.default = (uci_cursor:get("nezha-agent-v1", "config", "gpu") == "1") or false
o:depends("config_mode", "preset")

-- hard_drive_partition_allowlist
o = s:taboption("advanced", Value, "hard_drive_partition_allowlist", translation_map["hard_drive_partition_allowlist"])
o.description = translate("输入多个分区路径，用逗号分隔，例如: /,/home,/data")
o.default = uci_cursor:get("nezha-agent-v1", "config", "hard_drive_partition_allowlist") or ""
o:depends("config_mode", "preset")

-- ip_report_period
o = s:taboption("advanced", Value, "ip_report_period", translate("IP报告周期(秒)"))
o.default = tonumber(uci_cursor:get("nezha-agent-v1", "config", "ip_report_period")) or 1800
o.datatype = "uinteger"
o:depends("config_mode", "preset")

-- nic_allowlist
o = s:taboption("advanced", Value, "nic_allowlist", translation_map["nic_allowlist"])
o.description = translate("输入网卡名称，用逗号分隔，例如: wan,lan")
o.default = uci_cursor:get("nezha-agent-v1", "config", "nic_allowlist") or ""
o:depends("config_mode", "preset")

-- report_delay
o = s:taboption("advanced", Value, "report_delay", translate("报告延迟(秒)"))
o.default = tonumber(uci_cursor:get("nezha-agent-v1", "config", "report_delay")) or 3
o.datatype = "uinteger"
o:depends("config_mode", "preset")

-- self_update_period
o = s:taboption("advanced", Value, "self_update_period", translation_map["self_update_period"])
o.default = tonumber(uci_cursor:get("nezha-agent-v1", "config", "self_update_period")) or 0
o.datatype = "uinteger"
o:depends("config_mode", "preset")

-- skip_connection_count
o = s:taboption("advanced", Flag, "skip_connection_count", translate("禁用网络连接数监控"))
o.default = (uci_cursor:get("nezha-agent-v1", "config", "skip_connection_count") == "1") or false
o:depends("config_mode", "preset")

-- skip_procs_count
o = s:taboption("advanced", Flag, "skip_procs_count", translate("禁用进程数监控"))
o.default = (uci_cursor:get("nezha-agent-v1", "config", "skip_procs_count") == "1") or false
o:depends("config_mode", "preset")

-- temperature
o = s:taboption("advanced", Flag, "temperature", translate("启用温度监控"))
o.default = (uci_cursor:get("nezha-agent-v1", "config", "temperature") == "1") or false
o:depends("config_mode", "preset")

-- use_gitee_to_upgrade
o = s:taboption("advanced", Flag, "use_gitee_to_upgrade", translation_map["use_gitee_to_upgrade"])
o.default = (uci_cursor:get("nezha-agent-v1", "config", "use_gitee_to_upgrade") == "1") or false
o:depends("config_mode", "preset")

-- use_ipv6_country_code
o = s:taboption("advanced", Flag, "use_ipv6_country_code", translation_map["use_ipv6_country_code"])
o.default = (uci_cursor:get("nezha-agent-v1", "config", "use_ipv6_country_code") == "1") or false
o:depends("config_mode", "preset")

return m
