require 'yaml'
require 'net/http'
require 'json'

class Enumerator
	def stopped?
		peek
		false
	rescue StopIteration
		true
	end
end

class String
	def like_int?
		/\A\d+\z/ === self
	end
end

module Lyricat

	DIFF = (1..5).map { [_1, %i[_ diffe diffn diffh diffm diffsp][_1]] }.to_h.freeze
	CONFIG = YAML.load_file(File.join(__dir__, 'config.yml'), symbolize_names: true).freeze
	LANGS = %i[tw cn jp eng].freeze

	def self.res symbol, *args
		base_path = ENV['LYRICAT_RES_BASE_PATH'] || __dir__
		path = File.expand_path sprintf(CONFIG[:res][symbol], *args), base_path
		File.exist?(path) ? File.read(path) : nil
	end

	def self.sheet symbol
		base_path = ENV['LYRICAT_RES_BASE_PATH'] || __dir__
		YAML.load_file(File.expand_path(CONFIG[:res][symbol], base_path), symbolize_names: true)[:MonoBehaviour][:dataArray]
	end

	class Song
		FIELDS = %i[song_id name singer writer diff label origin update_version year lyrics lyrics_b].freeze
		DIFF_FORMATS = %i[in_game precise in_game_and_precise in_game_and_abbr_precise].freeze
		DIFF_NAME_FORMATS = %i[id in_game field].freeze

		attr_reader :index, :update_version, :year, :label_id
		attr_reader :diff
		
		def initialize hash
			@index = hash[:index]
			@update_version = hash[:updateversion]
			@year = hash[:addyear]
			@label_id = hash[:labelid]
			@name = {tw: hash[:songname], cn: hash[:songnamecn], jp: hash[:songnamejp], eng: hash[:songnameeng]}
			@singer = {tw: hash[:singer], cn: hash[:singercn], jp: hash[:singerjp], eng: hash[:singereng]}
			@writer = {tw: hash[:songwriter], cn: hash[:songwritercn], jp: hash[:songwriterjp], eng: hash[:songwritereng]}
			@origin = {tw: hash[:originallyrics], cn: hash[:originallyricscn], jp: hash[:originallyricsjp], eng: hash[:originallyricseng]}
			@diff = {}
			DIFF.each do |diff_id, diff_sym|
				@diff[diff_id] = hash[diff_sym] if hash[diff_sym] >= 0
			end
		end

		def major
			@update_version[0].to_i
		end

		def new?
			major == self.class.max_version
		end

		def old?
			major < self.class.max_version
		end

		def mr diff_id, session_token
			leaderboard = HeavyLifting.get_my_leaderboard session_token, @index, diff_id
			mr_by_score diff_id, leaderboard[:score]
		end

		def mr_by_score diff_id, score
			d = @diff[diff_id]
			s = score / 1e4
			return 0.0 if s < 50
			(s >= 98 ? d+2 - (100-s)/2 : [0, d+1 - (98-s)/4].max).round 6
		end

		def name lang = LANGS.first
			@name[lang]
		end

		def singer lang = LANGS.first
			@singer[lang]
		end

		def writer lang = LANGS.first
			@writer[lang]
		end

		def origin lang = LANGS.first
			@origin[lang]
		end
		
		def label lang = LANGS.first
			LABELS[@label_id][lang]
		end

		def lyrics
			Lyricat.res(:songlyrics, @index)&.gsub! "\r\n", ?\n
		end

		def lyrics_b
			Lyricat.res(:songlyrics_b, @index)&.gsub! "\r\n", ?\n
		end

		def diff lang = LANGS.first, format = :precise, name_format = :id
			@diff.map do |diff_id, diff|
				key = case name_format
				when :id then diff_id
				when :in_game then DIFFS_NAME[diff_id][lang]
				when :field then DIFF[diff_id]
				end
				value = case format
				when :precise then diff
				when :in_game then DIFFS_IN_GAME[diff_id][lang]
				when :in_game_and_precise
					in_game = DIFFS_IN_GAME[diff.to_i][lang]
					in_game += DIFF_PLUS[lang] if diff % 1 > 0.5
					"#{in_game} (#{diff})"
				when :in_game_and_abbr_precise
					in_game = DIFFS_IN_GAME[diff.to_i][lang]
					in_game += DIFF_PLUS[lang] if diff % 1 > 0.5
					"#{in_game}(.#{(diff % 1 * 10).round})"
				end
				[key, value]
			end.to_h
		end

		def song_id
			@index
		end

		def get_field field, lang = LANGS.first, diff_format = :precise, diff_name_format = :id
			return diff lang, diff_format, diff_name_format if field == :diff
			meth = method field
			meth.arity == 0 ? meth.() : meth.(lang)
		end

		class << self
			attr_accessor :max_version

			def add_song hash, lib
				return unless hash[:index].is_a? Integer
				return unless hash[:updateversion].is_a? String
				song = Song.new hash
				@max_version = [@max_version || 0, song.major].max
				lib[song.index] = song
			end

			def get_sorted &filter
				LIB.map do |song|
					song && filter.(song) ? song.diff.filter { _2 < 15 }.map { |i, d| [song.index, i] } : []
				end.flatten!(1).sort_by! { -LIB[_1].diff[_2] }
			end

			def best n, sorted, session_token
				picked = {}
				records = {}
				queue = Thread::Queue.new
				mutex = Thread::Mutex.new
				production = Thread.new do
					managing_queue = Thread::Queue.new
					schedule = sorted.each_with_index
					schedule_mutex = Thread::Mutex.new
					threads = Set.new
					threads_mutex = Thread::Mutex.new
					unnecessary = Set.new
					unnecessary_mutex = Thread::Mutex.new
					should_stop = false
					create_thread = proc do
						next if schedule_mutex.synchronize { schedule.stopped? } || should_stop
						(song_id, diff_id), i = schedule_mutex.synchronize { schedule.next }
						song = LIB[song_id]
						next should_stop = true if mutex.synchronize { picked.size >= n && records[picked[picked.keys[n-1]]][1] >= song.diff[diff_id] + 2 }
						unnecessary_mutex.synchronize { unnecessary.add i } and redo if mutex.synchronize { picked_i = picked[song_id] and records[picked_i][1] >= song.diff[diff_id] + 2 }
						thread = Thread.new do
							leaderboard = HeavyLifting.get_my_leaderboard session_token, song_id, diff_id
							score = leaderboard[:score]

							mr = LIB[song_id].mr_by_score diff_id, score
							mutex.synchronize { records[i] = [score, mr] }
							p [i, song_id, diff_id, score, mr]
							managing_queue.push i
							threads.delete Thread.current
						end
						threads_mutex.synchronize { threads.add thread }
					end
					create_thread.() until threads_mutex.synchronize { threads.size == THREADS } || schedule_mutex.synchronize { schedule.stopped? }
					sorted.size.times.with_object Set.new do |i, products|
						queue.push i unless until products.include? i
							break true if managing_queue.empty? && threads_mutex.synchronize { threads.empty? } or unnecessary_mutex.synchronize { unnecessary.include? i }
							products.add managing_queue.shift
							create_thread.()
						end
					end
				end
				until queue.empty? && !production.status
					next unless i = queue.shift
					song_id, diff_id = sorted[i]
					song = LIB[song_id]
					next if mutex.synchronize { (picked_i = picked[song_id]) && records[i][1] <= records[picked_i][1] }
					mutex.synchronize do
						picked[song_id] = i
						picked = picked.sort_by { -records[_2][1] }.to_h
					end
				end
				picked.take(n).map do |song_id, i|
					song_id, diff = sorted[i]
					score, mr = records[i]
					song = LIB[song_id]
					{song_id:, diff_id: diff, score:, mr:}
				end.filter { _1[:mr] > 0 }
			end
		end

		LIB = Lyricat.sheet(:song_lib).each_with_object [], &method(:add_song).freeze
		SORTED_OLD = get_sorted(&:old?).freeze
		SORTED_NEW = get_sorted(&:new?).freeze
		THREADS = 64

		lang_sheet = Lyricat.sheet :language
		begin item = lang_sheet.shift end until item[:index] == '#' && item[:tw] == 1
		DIFFS_IN_GAME = ((1..10).map { |i| [i, lang_sheet[i-1]] } + (11..15).map { |i| [i, lang_sheet[i+43]] }).to_h.freeze
		DIFFS_NAME = ((1..4).map { |i| [i, lang_sheet[i+9]] } + [[5, lang_sheet[53]]]).to_h.freeze
		DIFF_PLUS = lang_sheet[59].tap { _1.delete :index }.freeze
		DIFFS_IN_GAME.each_value { _1.delete :index }
		DIFFS_NAME.each_value { _1.delete :index }

		begin item = lang_sheet.shift end until item[:index] == '#' && item[:tw] == 9
		LABELS = lang_sheet.each_with_object({}).reduce false do |negative, (item, labels)|
			negative ? (break labels) : (next true) if item[:index] == '#'
			index = item[:index]
			index = negative ? index > 5 ? -4 - index : -1 - index : index
			labels[index] = item
			labels[index].delete :index
			negative
		end.freeze
	end

	module HeavyLifting

		class BadUpstreamResponse < StandardError
		end

		module_function

		def make_net
			net = Net::HTTP.new CONFIG[:upstream][:domain], CONFIG[:upstream][:port]
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

		def get_user session_token
			net = make_net
			response = net.request make_get_request '/parse/sessions/me', session_token
			raise BadUpstreamResponse unless response.code == '200'
			me = JSON.parse response.body, symbolize_names: true

			raise BadUpstreamResponse unless me[:user].is_a? Hash
			class_name, object_id = me[:user].values_at :className, :objectId
			response = net.request make_get_request "/parse/classes/#{class_name}/#{object_id}", session_token
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
			raise BadUpstreamResponse unless columns.size == 5
			scores, nicknames, heads = columns[0..2].map { _1.split ?' }
			raise BadUpstreamResponse unless scores.size == nicknames.size && nicknames.size == heads.size
			scores.map! &:to_i
			heads.map! &:to_i
			scores.zip(nicknames, heads).each_with_index.map { |(score, nickname, head), i| {score:, nickname:, head:, rank: i+1} }
		end

		def get_leaderboard session_token, song_id, diff_id
			net = make_net
			response = net.request make_post_request '/parse/functions/AskLeaderBoardNew', session_token, diff: diff_id, score: 0, songId: song_id
			raise BadUpstreamResponse unless response.code == '200'

			body = JSON.parse response.body, symbolize_names: true
			raise BadUpstreamResponse unless body[:result].is_a? String
			process_leaderboard body[:result]
		end

		def get_my_leaderboard session_token, song_id, diff_id
			net = make_net
			response = net.request make_post_request '/parse/functions/AskMyLeaderBoard', session_token, diff: diff_id, score: 0, songId: song_id
			raise BadUpstreamResponse unless response.code == '200'

			body = JSON.parse response.body, symbolize_names: true
			raise BadUpstreamResponse unless body[:result].is_a? String
			zero, score, rank, diff_id, song_id, extra = body[:result].split ','
			{score: score.to_i, rank: rank.to_i, diff_id: diff_id.to_i, song_id: song_id.to_i}
		end

		def get_month_leaderboard session_token, song_id, diff_id
			net = make_net
			response = net.request make_post_request '/parse/functions/AskMonthLeaderBoardNew', session_token, diff: diff_id, score: 0, songId: song_id
			raise BadUpstreamResponse unless response.code == '200'

			body = JSON.parse response.body, symbolize_names: true
			raise BadUpstreamResponse unless body[:result].is_a? String
			process_leaderboard body[:result]
		end

		def get_my_month_leaderboard session_token, song_id, diff_id
			net = make_net
			response = net.request make_post_request '/parse/functions/AskMyMonthLeaderBoard', session_token, diff: diff_id, score: 0, songId: song_id
			raise BadUpstreamResponse unless response.code == '200'

			body = JSON.parse response.body, symbolize_names: true
			raise BadUpstreamResponse unless body[:result].is_a? String
			zero, score, rank, diff_id, song_id, extra = body[:result].split ','
			{score: score.to_i, rank: rank.to_i, diff_id: diff_id.to_i, song_id: song_id.to_i}
		end
	end

	class BadOptions < StandardError
	end

	module DynamicAPI
		module_function

		def user session_token, **opts
			HeavyLifting.get_user session_token
		end

		def b35 session_token, **opts
			Song.best 35, Song::SORTED_OLD, session_token
		end

		def b15 session_token, **opts
			Song.best 15, Song::SORTED_NEW, session_token
		end

		def b50 session_token, **opts
			[*b35(session_token), *b15(session_token)]
		end

		def mr session_token, **opts
			details = opts[:details]
			details = [] unless details.is_a? Array
			b35 = b35 session_token
			b15 = b15 session_token
			b50 = [*b35, *b15]
			result = {mr: (b50.sum { _1[:mr] } / 50).round(8)}
			result[:b35] = b35 if details.include? 'b35'
			result[:b15] = b15 if details.include? 'b15'
			result[:b50] = b50 if details.include? 'b50'
			result
		end

		def leaderboard session_token, **opts
			raise BadOptions unless (song_id = opts[:song_id]).is_a? Integer
			raise BadOptions unless (diff_id = opts[:diff_id]).is_a? Integer
			song = Song::LIB[song_id]
			return unless song && song.diff[diff_id]
			HeavyLifting.get_my_leaderboard session_token, song_id, diff_id
		end

		def month_leaderboard session_token, **opts
			raise BadOptions unless (song_id = opts[:song_id]).is_a? Integer
			raise BadOptions unless (diff_id = opts[:diff_id]).is_a? Integer
			song = Song::LIB[song_id]
			return unless song && song.diff[diff_id]
			HeavyLifting.get_my_leaderboard session_token, song_id, diff_id
		end

		def song session_token, **opts
			raise BadOptions unless (song_id = opts[:song_id]).is_a? Integer
			song = Song::LIB[song_id]
			return unless song
			scores_mutex = Thread::Mutex.new
			mrs_mutex = Thread::Mutex.new
			scores = {}
			mrs = {}
			song.diff.map do |diff_id, diff|
				Thread.new do
					leaderboard = HeavyLifting.get_my_leaderboard session_token, song_id, diff_id
					scores_mutex.synchronize { scores[diff_id] = leaderboard[:score] }
					mrs_mutex.synchronize { mrs[diff_id] = song.mr_by_score diff_id, leaderboard[:score] }
				end
			end.each &:join
			{song_id:, name: song.name, singer: song.singer, writer: song.writer, diff: song.diff, scores:, mrs:}
		end
	end

	module StaticAPI
		SESSION_TOKEN = ENV['LYRICAT_STATIC_SESSION_TOKEN'].freeze
		raise 'LYRICAT_STATIC_SESSION_TOKEN not set' unless SESSION_TOKEN

		module_function

		def leaderboard **opts
			raise BadOptions.new 'song_id must be integer' unless (song_id = opts[:song_id]).is_a? Integer
			raise BadOptions.new 'diff_id must be integer' unless (diff_id = opts[:diff_id]).is_a? Integer
			song = Song::LIB[song_id]
			return unless song && song.diff[diff_id]
			HeavyLifting.get_leaderboard SESSION_TOKEN, song_id, diff_id
		end

		def month_leaderboard **opts
			raise BadOptions.new 'song_id must be integer' unless (song_id = opts[:song_id]).is_a? Integer
			raise BadOptions.new 'diff_id must be integer' unless (diff_id = opts[:diff_id]).is_a? Integer
			song = Song::LIB[song_id]
			return unless song && song.diff[diff_id]
			HeavyLifting.get_month_leaderboard SESSION_TOKEN, song_id, diff_id
		end

		def song **opts
			raise BadOptions.new 'song_id must be integer' unless (song_id = opts[:song_id]).is_a? Integer
			song = Song::LIB[song_id]
			return unless song

			raise BadOptions.new 'fields must be array of strings' if (fields = opts[:fields]) && (!fields.is_a?(Array) || !fields.all? { _1.is_a? String })
			fields ||= %w[song_id name singer writer diff label origin update_version year]
			fields.map! &:to_sym
			if unknown_field = fields.find { |field| !Song::FIELDS.include?(field) }
				raise BadOptions.new "unknown field: #{unknown_field}"
			end

			raise BadOptions.new 'diff_format must be a string' if (diff_format = opts[:diff_format]) && !diff_format.is_a?(String)
			diff_format ||= 'in_game_and_abbr_precise'
			diff_format = diff_format.to_sym
			raise BadOptions.new "unknown diff_format: #{diff_format}" unless Song::DIFF_FORMATS.include? diff_format

			raise BadOptions.new 'diff_name_format must be a string' if (diff_name_format = opts[:diff_name_format]) && !diff_name_format.is_a?(String)
			diff_name_format ||= 'in_game'
			diff_name_format = diff_name_format.to_sym
			raise BadOptions.new "unknown diff_name_format: #{diff_name_format}" unless Song::DIFF_NAME_FORMATS.include? diff_name_format

			raise BadOptions.new 'lang must be a string' if (lang = opts[:lang]) && !lang.is_a?(String)
			lang ||= 'tw'
			lang = lang.to_sym
			raise BadOptions.new "unknown lang: #{lang}" unless LANGS.include? lang

			fields.map { |field| [field, song.get_field(field, lang, diff_format, diff_name_format)] }.to_h
		end

	end
end

# p Lyricat::API.mr 'r:cbfde15f27c0229cb21745161deeb4e7', details: %w[b35 b15]
# r:19c47755be896db65b5991bfb3f207a4
