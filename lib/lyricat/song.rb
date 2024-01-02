# frozen_string_literal: true

module Lyricat
	class Song
		FIELDS = %i[song_id name singer writer diff label origin update_version year lyrics].freeze
		DIFF_FORMATS = %i[in_game precise in_game_and_precise in_game_and_abbr_precise].freeze
		DIFF_NAME_FORMATS = %i[id in_game field].freeze

		attr_reader :index, :update_version, :year, :label_id, :romanized
		attr_reader :diff
		
		def initialize hash
			@index = hash[:index]
			@update_version = hash[:updateversion]
			@year = hash[:addyear]
			@label_id = hash[:labelid]
			@name = {tw: hash[:songname], cn: hash[:songnamecn], jp: hash[:songnamejp], eng: hash[:songnameeng]}
			@name.transform_values! { _1.split('|').last.gsub ?\n, ' '}
			@singer = {tw: hash[:singer], cn: hash[:singercn], jp: hash[:singerjp], eng: hash[:singereng]}
			@writer = {tw: hash[:songwriter], cn: hash[:songwritercn], jp: hash[:songwriterjp], eng: hash[:songwritereng]}
			@origin = {tw: hash[:originallyrics], cn: hash[:originallyricscn], jp: hash[:originallyricsjp], eng: hash[:originallyricseng]}
			@diff = {}
			DIFF.each do |diff_id, diff_sym|
				@diff[diff_id] = hash[diff_sym] if hash[diff_sym] >= 0
			end
			@ascii_name = @name.transform_values { AnyAscii.transliterate _1 }
			@lyrics = (LYRICS[@index] || {}).then { { tw: _1[:lyrics], cn: _1[:lyricscn], jp: _1[:lyricsjp], eng: _1[:lyricseng] } }
			@lyrics.transform_values! { _1&.gsub "\r\n", ?\n }
			@lyrics_info = (LYRICS_INFO[@index] || {}).then { { tw: _1[:lyricsinfo], cn: _1[:lyricsinfocn], jp: _1[:lyricsinfojp], eng: _1[:lyricsinfoeng] } }
			Singer::LIB[hash[:singerid]]&.songs&.push @index
		end

		def match_roman1 query, strong, lang = nil
			query = query.gsub(/\s/, '').downcase
			meth = strong ? :== : :include?
			values = lang ? [@ascii_name[lang]] : @ascii_name.values
			return true if values.any? { |roman| roman.gsub(/\s/, '').downcase.__send__ meth, query }
			return true if values.any? { |roman| roman.gsub(/[^\w]/, '').downcase.__send__ meth, query }
			false
		end

		def match_roman2 query, strong, lang = nil
			query = query.gsub(/\s/, '').downcase
			meth = strong ? :== : :include?
			values = lang ? [@ascii_name[lang]] : @ascii_name.values
			return true if values.any? { |roman| roman.upper_letters.__send__ meth, query }
			return true if values.any? { |roman| (words = roman.split).length > 1 && words.map { _1[0] }.join.downcase.__send__(meth, query) }
			return true if values.any? { |roman| (words = roman.split /[^\w]/).length > 1 && words.map { _1[0] }.join.downcase.__send__(meth, query) }
			false
		end

		def match_name query, strong, lang = nil
			query = query.strip.downcase
			meth = strong ? :== : :include?
			values = lang ? [@name[lang]] : @name.values
			return true if values.any? { _1.strip.__send__ meth, query }
			return true if values.any? { _1.gsub(/[^\w]/, '').__send__ meth, query }
			false
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

		def lyrics lang = LANGS.first
			@lyrics[lang]
		end

		def lyrics_info lang = LANGS.first
			@lyrics_info[lang]
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

		def info_inspect lang = LANGS.first, diff_format = :in_game_and_abbr_precise, diff_name_format = :id
			<<~EOF
				**ID**\t#{song_id}
				**Name**\t#{name lang}
				**Singer**\t#{singer lang}
				**Writer**\t#{writer(lang)&.gsub(?\n, ' / ')&.gsub('__', ' ')}
				**Difficulties**\t#{diff(lang, diff_format, diff_name_format).values.join " / "}
				**Label**\t#{label lang}
				**Origin**\t#{origin(lang)&.gsub(?\n, ' ')}
				**Update version**\t#{update_version}
				**Year**\t#{year}
			EOF
		end

		class << self
			attr_accessor :max_version

			def add_song hash, lib
				return unless hash[:index].is_a? Integer
				return unless hash[:updateversion].is_a? String
				return unless hash[:songname].is_a? String and hash[:songname].length > 0
				song = Song.new hash
				@max_version = [@max_version || 0, song.major].max
				lib[song.index] = song
			end

			def get_sorted &filter
				LIB.map do |_, song|
					song && filter.(song) ? song.diff.filter { _2 < 15 }.map { |i, d| [song.index, i] } : []
				end.flatten!(1).sort_by! { -LIB[_1].diff[_2] }
			end

			def best n, sorted, session_token
				picked = Concurrent::Hash.new
				records = Concurrent::Hash.new
				queue = Thread::Queue.new
				threads = Concurrent::Hash.new
				threads_mutex = Thread::Mutex.new
				unnecessary = Concurrent::Set.new
				currently_wanted = nil
				production = Thread.new do
					managing_queue = Thread::Queue.new
					schedule = Concurrent::Array[*sorted.each_with_index]
					should_stop = false
					create_thread = proc do
						next if schedule.empty? || should_stop
						(song_id, diff_id), i = schedule.shift
						song = LIB[song_id]
						next should_stop = true if picked.size >= n && records[picked[picked.keys[n-1]]][1] >= song.diff[diff_id] + 2
						unnecessary.add i and redo if picked_i = picked[song_id] and records[picked_i][1] >= song.diff[diff_id] + 2
						thread = Thread.new do
							begin
								leaderboard = HeavyLifting.get_my_leaderboard session_token, song_id, diff_id
								score = leaderboard[:score]
							rescue Net::OpenTimeout
								puts "Timeout when querying #{i}, #{song_id}, #{diff_id}"
								score = 0
							end
							
							mr = LIB[song_id].mr_by_score diff_id, score
							records[i] = [score, mr]
							p [i, song_id, diff_id, score, mr]
							# puts "FEEDING #{i}"
							managing_queue.push i
						end
						thread.abort_on_exception = true
						threads_mutex.synchronize { threads[i] = thread }
					end
					create_thread.() until threads.size == THREADS || schedule.empty?
					sorted.size.times.with_object Concurrent::Set.new do |i, products|
						#puts "WANT #{i}"
						case until products.include?(currently_wanted = i)
							break :nothing_left if managing_queue.empty? and threads.none? { _2.status }
							break :unnecessary if unnecessary.include? i
							products.add managing_queue.shift
							create_thread.()
						end
						when :nothing_left then break
						when :unnecessary then next
						end
						#puts "PRODUCING #{i}; in queue: #{queue.length}"
						queue.push i
					end
				end
				while queue.length != 0 || production.status and i = queue.shift
					#puts "CONSUMING #{i}; in queue: #{queue.length}"
					song_id, diff_id = sorted[i]
					song = LIB[song_id]
					next if (picked_i = picked[song_id]) && records[i][1] <= records[picked_i][1]
					picked[song_id] = i
					picked = picked.sort_by { -records[_2][1] }.to_h
					# puts picked.keys.join ' '
					threads_mutex.synchronize do
						threads.delete_if do |j, thread|
							next true unless thread.status
							next false if j == currently_wanted || records[picked[picked.keys[n-1]]][1] < song.diff[diff_id] + 2
							#puts "killing #{j}, #{sorted[j].join ', '}"
							unnecessary.add j
							thread.kill
						end
					end if picked.size >= n
				end
				picked.take(n).map do |song_id, i|
					song_id, diff = sorted[i]
					score, mr = records[i]
					song = LIB[song_id]
					{song_id:, diff_id: diff, score:, mr:}
				end.filter { _1[:mr] > 0 }
			end

			def fuzzy_search lang, query
				if query.like_int?
					id = query.to_i
					return id if LIB[id]
				end
				[lang, nil].each do |l|
					if o = LIB.find { _2.match_name query, true, l }
						return o[0]
					end
					if o = LIB.find { _2.match_roman1 query, true, l }
						return o[0]
					end
					if o = LIB.find { _2.match_roman2 query, true, l }
						return o[0]
					end
					if o = LIB.find { _2.match_roman1 query, false, l }
						return o[0]
					end
					if o = LIB.find { _2.match_roman2 query, false, l }
						return o[0]
					end
					if o = LIB.find { _2.match_name query, false, l }
						return o[0]
					end
				end
				nil
			end

			def random min, max
				LIB.filter { |_, song| song.diff.values.any? { |d| d >= min && d < max } }.keys.sample
			end
		end

		LYRICS = Lyricat.sheet(:lyrics).each_with_object({}) { |hash, lib| lib[hash[:index]] = hash }.freeze
		LYRICS_INFO = Lyricat.sheet(:lyrics_info).each_with_object({}) { |hash, lib| lib[hash[:index]] = hash }.freeze
		LIB = Lyricat.sheet(:song_lib).each_with_object({}, &method(:add_song)).freeze
		SORTED_OLD = get_sorted(&:old?).freeze
		SORTED_NEW = get_sorted(&:new?).freeze
		THREADS = ENV['LYRICAT_THREADS_COUNT']&.to_i || 8

		lang_sheet = Lyricat.sheet :language
		begin item = lang_sheet.shift end until item[:index] == '#' && item[:tw] == 1
		DIFFS_IN_GAME = ((1..10).map { |i| [i, lang_sheet[i-1].transform_values(&:to_s)] } + (11..15).map { |i| [i, lang_sheet[i+43].transform_values(&:to_s)] }).to_h.freeze
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

end
