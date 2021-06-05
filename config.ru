require 'dashing'

configure do
  set :auth_token, 'YOUR_AUTH_TOKEN'
  set :template_languages, %i[html erb]
  set :show_exceptions, false
end

map Sinatra::Application.assets_prefix do
  run Sinatra::Application.sprockets
end

run Sinatra::Application
