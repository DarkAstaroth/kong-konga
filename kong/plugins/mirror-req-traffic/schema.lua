local PLUGIN_NAME = "mirror-req-traffic"

local typedefs = require "kong.db.schema.typedefs"

local schema = {
  name = PLUGIN_NAME,
  fields = {
    { config = {
        type = "record",
        fields = {
          { mirror_url = {
              type = "string",
              required = true,
              default = "https://mirror_url.example.com",
              -- match = "^https?://",
              err = "debe ser una URL válida (http o https)"
            }
          },
          { connect_timeout = {
              type = "number",
              required = false,
              default = 2000,
              gt = 0,
              description = "Tiempo de espera para la conexión en milisegundos"
            }
          },
          { ssl_verify = {
              type = "boolean",
              required = false,
              default = true,
              description = "Verificar certificados SSL"
            }
          },
        },
      },
    },
  },
}


return schema
