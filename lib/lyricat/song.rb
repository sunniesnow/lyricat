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
				when :in_game then Song.diff_name_in_game diff_id, lang
				when :field then DIFF[diff_id]
				end
				value = case format
				when :precise then diff
				when :in_game then DIFFS_IN_GAME[diff_id][lang]
				when :in_game_and_precise then Song.diff_in_game_and_precise diff, lang, special: diff_id == 5
				when :in_game_and_abbr_precise then Song.diff_in_game_and_abbr_precise diff, lang, special: diff_id == 5
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

			def diff_in_game_and_abbr_precise diff, lang = LANGS.first, special: false
				if special.nil?
					in_game = [DIFFS_IN_GAME[diff.to_i], DIFFS_SP_IN_GAME[diff.to_i]].compact.map { _1[lang] }.join '/'
				else
					in_game = (special ? DIFFS_SP_IN_GAME : DIFFS_IN_GAME)[diff.to_i][lang]
				end
				in_game += DIFF_PLUS[lang] if diff % 1 > 0.5
				"#{in_game}(.#{(diff % 1 * 10).round})"
			end

			def diff_in_game_and_precise diff, lang = LANGS.first, special: false
				in_game = (special ? DIFFS_SP_IN_GAME : DIFFS_IN_GAME)[diff.to_i][lang]
				in_game += DIFF_PLUS[lang] if diff % 1 > 0.5
				"#{in_game} (#{diff})"
			end

			def diff_name_in_game diff_id, lang = LANGS.first
				DIFFS_NAME[diff_id][lang]
			end

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
				bad_upstream = false
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
							rescue HeavyLifting::BadUpstreamResponse => e
								unless bad_upstream
									bad_upstream = e
									puts "Bad upstream response when querying #{i}, #{song_id}, #{diff_id}"
									production.kill
									queue.close
									Thread.new { threads.each_value &:kill }
									thread.exit
								end
							end

							mr = LIB[song_id].mr_by_score diff_id, score
							records[i] = [score, mr]
							p [i, song_id, diff_id, score, mr]
							# puts "FEEDING #{i}"
							managing_queue.push i
						end
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
				raise bad_upstream if bad_upstream
				picked.take(n).map do |song_id, i|
					song_id, diff = sorted[i]
					score, mr = records[i]
					song = LIB[song_id]
					{song_id:, diff_id: diff, score:, mr:}
				end.filter { _1[:mr] > 0 }
			end

			def fuzzy_search lang, query, excluded = []
				if query.like_int?
					id = query.to_i
					return id if LIB[id]
				end
				if from_alias = ALIASES[query]
					return from_alias
				end
				get_forms = ->original do
					ascii = AnyAscii.transliterate original
					abbr0 = ascii.upper_letters
					abbr0 = nil if abbr0.length <= 1
					abbr1 = original.split.map { _1[0] }.join
					abbr1 = nil if abbr1.length <= 1
					abbr2 = original.split(/[^\w]/).map { _1[0] }.join
					abbr2 = nil if abbr2.length <= 1
					abbr3 = original.upper_letters
					abbr3 = nil if abbr3.length <= 1
					[original, ascii, abbr0, abbr1, abbr2, abbr3].compact
				end
				query_forms = get_forms.(query)
				if query =~ /^(.*?)(\d+)$/
					n = $2.to_i
					alter_forms = get_forms.($1) if n > 1
					searched = Set.new
				end
				filtered_lib = LIB.reject { excluded.include? _2.song_id }
				[lang, nil].each do |l|
					match = ->meth, strong = false do
						query_forms.zip alter_forms.to_a do |form, alter_form|
							found = filtered_lib.find do |song_id, song|
								song.__send__ meth, form, strong, l
							end&.first
							found ||= filtered_lib.find do |song_id, song|
								if song.__send__(meth, alter_form, strong, l)
									searched.add song_id
									next true if n == searched.size
								end
							end&.first if alter_form
							return found if found
						end
						nil
					end
					o = match.(:match_name, true) || match.(:match_name) || match.(:match_roman1, true) || match.(:match_roman2, true) || match.(:match_roman1) || match.(:match_roman2)
					return o if o
				end
				nil
			end

			def parse_difficulty_query *query
				min, max = query
				max ||= min || '14'
				min ||= '1'
				min = min.like_int? ? min.to_i : min.like_float? ? min.to_f : (return [])
				max = max.like_int? ? max.to_i : max.like_float? ? max.to_f : (return [])
				min, max = max, min if min > max
				max += max.is_a?(Integer) ? 1 : 0.1
				[min, max]
			end

			def select_songs_by_difficulty_query *query
				min, max = parse_difficulty_query *query
				return nil unless min && max
				LIB.filter { |_, song| song.diff.values.any? { |d| d >= min && d < max } }.keys
			end

			def select_charts_by_difficulty diff, &block
				return to_enum :select_charts_by_difficulty, diff unless block
				LIB.each_with_object [] do |(song_id, song), result|
					song.diff.each do |diff_id, diff_value|
						block.(song_id, diff_id) if diff_value == diff
					end
				end
			end
		end

		LYRICS = Lyricat.sheet(:lyrics).each_with_object({}) { |hash, lib| lib[hash[:index]] = hash }.freeze
		LYRICS_INFO = Lyricat.sheet(:lyrics_info).each_with_object({}) { |hash, lib| lib[hash[:index]] = hash }.freeze
		LIB = Lyricat.sheet(:song_lib).each_with_object({}, &method(:add_song)).freeze
		SORTED_OLD = get_sorted(&:old?).freeze
		SORTED_NEW = get_sorted(&:new?).freeze
		THREADS = ENV['LYRICAT_THREADS_COUNT']&.to_i || 8

		lang_sheet = Lyricat.sheet(:language).each_with_object [] do |item, lib|
			item[:index] == ?# ? lib[item[:tw]] = [] : lib.last[item[:index]] = item.except(:index).transform_values(&:to_s).freeze
		end
		DIFFS_IN_GAME = (1..15).map { |i| [i, lang_sheet[1][i<=10 ? i-1 : i+43]] }.to_h.freeze
		DIFFS_SP_IN_GAME = (
			(1..14).map { |i| [i, lang_sheet[1][i<=10 ? i-1 : i+43]] } +
			lang_sheet[15].map.with_index { |item, i| [i+15, item] }
		).to_h.freeze
		DIFF_PLUS = lang_sheet[1][59]
		DIFFS_NAME = (1..5).map { |i| [i, lang_sheet[1][i<5 ? i+9 : 53]] }.to_h.freeze
		LABELS = (
			lang_sheet[9].map.with_index { |item, i| [i, item] } +
			lang_sheet[10].map.with_index { |item, i| [i>5 ? -4-i : -1-i, item] }
		).to_h.freeze

		ALIASES = YAML.load_file(File.join Lyricat::DATA_DIR, ENV['LYRICAT_ALIASES'] || 'aliases.yml')['songs']
		ALIASES.merge! ALIASES.transform_keys { Ropencc.conv 's2t', _1 }
		ALIASES.freeze
	end

end
