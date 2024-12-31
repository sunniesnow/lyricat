# frozen_string_literal: true

module Lyricat
	module HeavyLifting

		class BadUpstreamResponse < StandardError
		end

		RETRY_COUNT = ENV['LYRICAT_RETRY_COUNT']&.to_i || 3

		module_function

		def make_net
			net = Net::HTTP.new CONFIG[:upstream][:host], CONFIG[:upstream][:port]
			net.use_ssl = CONFIG[:upstream][:ssl]
			net
		end

		def make_post_request path, session_token, **body
			request = Net::HTTP::Post.new File.join CONFIG[:upstream][:base_url], path
			request['X-Parse-Application-Id'] = CONFIG[:app_id]
			request['X-Parse-Session-Token'] = session_token
			request['Content-Type'] = 'application/json'
			request.body = body.to_json
			request
		end

		def make_get_request path, session_token
			make_post_request path, session_token, _method: 'GET', _noBody: true
		end

		def make_put_request path, session_token, **body
			make_post_request path, session_token, _method: 'PUT', _noBody: false, **body
		end

		def request net, request
			RETRY_COUNT.times do
				return net.request request
			rescue Net::OpenTimeout
			end
			raise Net::OpenTimeout
		end

		def get_user session_token
			net = make_net
			response = request net, make_get_request('/parse/sessions/me', session_token)
			raise BadUpstreamResponse, "Response code is #{response.code} instead of 200" unless response.code == '200'
			me = JSON.parse response.body, symbolize_names: true

			raise BadUpstreamResponse, "The `user` field of the JSON is not a Hash but a #{me[:user].class}" unless me[:user].is_a? Hash
			class_name, object_id = me[:user].values_at :className, :objectId
			response = request net, make_get_request("/parse/classes/#{class_name}/#{object_id}", session_token)
			hash = JSON.parse response.body, symbolize_names: true
			username = hash[:username]
			created_at = hash[:createdAt]
			nickname = hash[:nickname]
			head = hash[:head].to_i
			{username:, created_at:, nickname:, head:}
		end

		def process_leaderboard result
			columns = result.split ?$
			columns.shift
			raise BadUpstreamResponse, "The leaderboard has #{columns.size} instead of 5 columns" unless columns.size == 5
			scores, nicknames, heads = columns[0..2].map { _1.split ?' }
			raise BadUpstreamResponse, "The leaderboard format is wrong because there are #{scores.size} scores, #{nicknames.size} nicknames, and #{heads.size} heads" unless scores.size == nicknames.size && nicknames.size == heads.size
			scores.map! &:to_i
			heads.map! &:to_i
			scores.zip(nicknames, heads).each_with_index.map { |(score, nickname, head), i| {score:, nickname:, head:, rank: i+1} }
		end

		def get_leaderboard session_token, song_id, diff_id
			net = make_net
			response = request net, make_post_request('/parse/functions/AskLeaderBoardNew', session_token, diff: diff_id, score: 0, songId: song_id)
			raise BadUpstreamResponse, "The response code is #{response.code} instead of 200" unless response.code == '200'

			body = JSON.parse response.body, symbolize_names: true
			raise BadUpstreamResponse, "The `result` field of the JSON is not a String but a #{body[:result].class}" unless body[:result].is_a? String
			process_leaderboard body[:result]
		end

		def get_my_leaderboard session_token, song_id, diff_id
			net = make_net
			response = request net, make_post_request('/parse/functions/AskMyLeaderBoard', session_token, diff: diff_id, score: 0, songId: song_id)
			raise BadUpstreamResponse, "The response code is #{response.code} instead of 200" unless response.code == '200'

			body = JSON.parse response.body, symbolize_names: true
			raise BadUpstreamResponse, "The `result` field of the JSON is not a String but a #{body[:result].class}" unless body[:result].is_a? String
			zero, score, rank, diff_id, song_id, extra = body[:result].split ','
			{score: score.to_i, rank: rank.to_i, diff_id: diff_id.to_i, song_id: song_id.to_i}
		end

		def get_month_leaderboard session_token, song_id, diff_id
			net = make_net
			response = request net, make_post_request('/parse/functions/AskMonthLeaderBoardNew', session_token, diff: diff_id, score: 0, songId: song_id)
			raise BadUpstreamResponse, "The response code is #{response.code} instead of 200" unless response.code == '200'

			body = JSON.parse response.body, symbolize_names: true
			raise BadUpstreamResponse, "The `result` field of the JSON is not a String but a #{body[:result].class}" unless body[:result].is_a? String
			process_leaderboard body[:result]
		end

		def get_my_month_leaderboard session_token, song_id, diff_id
			net = make_net
			response = request net, make_post_request('/parse/functions/AskMyMonthLeaderBoard', session_token, diff: diff_id, score: 0, songId: song_id)
			raise BadUpstreamResponse, "The response code is #{response.code} instead of 200" unless response.code == '200'

			body = JSON.parse response.body, symbolize_names: true
			raise BadUpstreamResponse, "The `result` field of the JSON is not a String but a #{body[:result].class}" unless body[:result].is_a? String
			zero, score, rank, diff_id, song_id, extra = body[:result].split ','
			{score: score.to_i, rank: rank.to_i, diff_id: diff_id.to_i, song_id: song_id.to_i}
		end

		def get_expiration_date session_token
			net = make_net
			response = request net, make_get_request('/parse/sessions/me', session_token)
			raise BadUpstreamResponse, "The response code is #{response.code} instead of 200" unless response.code == '200'
			me = JSON.parse response.body, symbolize_names: true
			iso = me[:expiresAt]&.[] :iso
			raise BadUpstreamResponse, "The JSON does not have `expiresAt.iso` field" unless iso
			begin
				return DateTime.parse iso
			rescue Date::Error
				raise BadUpstreamResponse, "Bad date format: #{iso}"
			end
		end
	end
end
