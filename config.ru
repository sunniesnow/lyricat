# frozen_string_literal: true

require_relative 'main'

class Lyricat::App
	def call env
		case env['REQUEST_METHOD']
		when 'POST'
		when 'OPTIONS'
			return [200, {'allow' => 'OPTIONS, POST'}, []]
		else
			return [405, {}, ["Method Not Allowed"]]
		end
		path = env['PATH_INFO']
		path = path[1..-1] if path.start_with? '/'
		path = path[0..-2] if path.end_with? '/'
		domain, method_name = path.split '/'
		api_receiver = {'static' => Lyricat::StaticAPI, 'dynamic' => Lyricat::DynamicAPI}[domain]
		unless api_receiver&.respond_to? method_name
			return [404, {}, ["Not Found"]]
		end
		begin
			json = JSON.parse env['rack.input'].read, symbolize_names: true
		rescue JSON::ParserError
			return [400, {}, ["Bad Request"]]
		end
		if domain == 'dynamic'
			unless json.is_a? Hash and json[:session_token].is_a? String
				return [400, {}, ["Bad Request"]]
			end
			if json[:options] && !json[:options].is_a?(Hash)
				return [400, {}, ["Bad Request"]]
			end
			header = [method_name, json[:session_token]]
			options = json[:options] || {}
		else
			unless json.is_a? Hash
				return [400, {}, ["Bad Request"]]
			end
			header = [method_name]
			options = json
		end

		begin
			body = api_receiver.send *header, **options
		rescue Lyricat::HeavyLifting::BadUpstreamResponse
			return [502, {}, ["Bad Gateway"]]
		rescue Lyricat::BadOptions => e
			return [400, {}, ["Bad Request: #{e.message}"]]
		end
		[200, {'content-type' => 'application/json'}, [body.to_json]]
	end
end

run Lyricat::App.new
