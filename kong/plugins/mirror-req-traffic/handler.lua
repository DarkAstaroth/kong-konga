local http = require "resty.http"
local cjson = require "cjson"

local get_raw_body = kong.request.get_raw_body

local MirrorReqTrafficHandler = {
  VERSION = "0.0.1",
  PRIORITY = 1500
}

function MirrorReqTrafficHandler:init_worker()
  kong.log.info("[init_worler] Iniciando el plugin MirrorReqTraffic")
end

local function deepCopy(original)
  if type(original) ~= "table" then
    return original
  end

  local copy = {}
  for key, value in pairs(original) do
    copy[deepCopy(key)] = deepCopy(value)
  end
  return copy
end


--- Replica datos de la solicitud a un servicio externo.
-- Esta función es asíncrona y se ejecuta mediante ngx.timer.at.
-- @param premature Boolean si el temporizador fue abortado.
-- @param conf Table con la configuración del plugin.
-- @param data Table con los datos recopilados de la solicitud.
-- @return nil
local function replicate(premature, conf, data, headers)
  -- kong.log.info('[replicate] Starting.....!!!')
  if premature then return end


  if not conf then
    kong.log.err("[replicate] No existe conf.")
    return
  end

  if not data then
    kong.log.err("[replicate] No existe datos")
    return
  end


  -- TODO: Analizar y validar el uso de una misma instancia HTTP
  local client   = http.new()
  local res, err = client:request_uri(conf.mirror_url, {
    method = 'POST',
    body = data,
    headers = {
      ["Content-Type"] = "application/json",
      ["Accept"] = "application/json",
    },
    ssl_verify = conf.ssl_verify,
  })

  if not res then
    kong.log.err("Error replicando la solicitud: ", err)
    return
  end

  kong.log.debug("Solicitud replicada con éxito: ", res.status)
  return
end

-- Captura datos de la solicitud en la fase access.
-- Recopila la información de la solicitud para replicarla más adelante.
-- @param conf Table con la configuración del plugin.
-- @return nil
function MirrorReqTrafficHandler:access(conf)
  -- kong.log.info('[Access]==============================')

  local method = kong.request.get_method()
  local path = kong.request.get_path()
  local query = kong.request.get_raw_query()
  local headers = kong.request.get_headers()
  local body, err = get_raw_body()

  if err then
    kong.log.err("Error al obtener el cuerpo de la solicitud: ", err)
    return
  end

  local request_id = ngx.var.request_id
  local headersLocal = deepCopy(headers)
  headersLocal['request_id'] = request_id

  local service = kong.router.get_service()
  local service_id
  if service then
    service_id = service.id
  else
    kong.log.warn("[access] No se pudo obtener el servicio.")
    service_id = '0'
  end

  kong.ctx.plugin.request_data = {
    method = method,
    headers = headersLocal,
    body = body,
    query = query,
    path = path,
    service = service_id,
  }
  return
end

function MirrorReqTrafficHandler:body_filter(conf)
  -- kong.log.info('[header_filter] =====================....!!!!!')
  local request_data = kong.ctx.plugin.request_data
  if not request_data then
    kong.log.warn('[header_filter] No se encontraron datos de la solicitud')
  end


  local status_code = kong.response.get_status()

  local via_header = kong.response.get_header("via")
  local upstream_status = via_header and true or false

  local request_id = kong.response.get_header("x-kong-request-id")
  local client_ip = kong.client.get_ip()
  local request_path = kong.request.get_path()


  local consumer_id = kong.request.get_header("X-Consumer-ID")
  if not consumer_id then
    kong.log.warn("[access] No se encontró X-Consumer-ID en las cabeceras.")
    consumer_id = '0'
  end
  local consumer_username = kong.request.get_header("x-consumer-username")
  if not consumer_username then
    kong.log.warn("[access] No se encontró c-consumer-username en las cabeceras.")
    consumer_username = 'NN'
  end

  local log_data = {
    general = {
      service = request_data.service,
      consumer = consumer_id,
      consumer_username = consumer_username,
      timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    },
    request = {
      method = request_data.method,
      path = request_data.path,
      headers = request_data.headers,
      body = request_data.body,
      query = request_data.query,
    },
    response = {
      status = status_code,
      upstream_status = upstream_status,
      request_id = request_id
    },
  }

  local mirror_url = conf.mirror_url .. request_path

  local json_body, err = cjson.encode(log_data)
  if not json_body then
    kong.log.err("[replicate] Error al codificar el cuerpo JSON: ", err)
    return
  end


  -- Control en el caso que la petición sea muy grande y se maneje por fragmentos
  -- evita duplicar las peticiones, solo envia al final
  local eof = ngx.arg[2]
  if eof then
    local ok, err = ngx.timer.at(0, replicate, conf, json_body, request_data.headers)
    if not ok then
      kong.log.err("Error al crear el timer para la replicación: ", err)
    end
  end
end

return MirrorReqTrafficHandler
