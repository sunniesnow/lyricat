# frozen_string_literal: true

module Lyricat
	module Bot

		SESSION_TOKEN = ENV['LYRICAT_STATIC_SESSION_TOKEN'].freeze
		raise 'LYRICAT_STATIC_SESSION_TOKEN not set' unless SESSION_TOKEN

		DB = SQLite3::Database.new File.join DATA_DIR, 'data.db'
		if DB.execute('select name from sqlite_master where type="table" and name="user"').empty?
			DB.execute 'create table user (id bigint primary key, session_token varchar(50), lang varchar(10), expiration bigint)'
		end
		DB.type_translation = true

		def self.run
			BOT.run
		end

		EXPIRATION_MARGIN = CONFIG[:expiration_margin]
		MAINTAINER_ID = ENV['LYRICAT_DISCORD_MAINTAINER_ID'] || 0

		def dynamic_command name, **opts, &block
			command name, **opts do |event, *query|
				id = event.user.id
				session_token, expiration = DB.get_first_row 'select session_token, expiration from user where id=?', id
				return 'Bind your session token first.' unless session_token
				return 'Session token expired. Please rebind.' if expiration < Time.now.to_f * 1000 + EXPIRATION_MARGIN
				begin
					block.(event, session_token, *query)
				rescue HeavyLifting::BadUpstreamResponse
					'Bad upstream response. Try binding a new session token?'
				end
			end
		end

		def gen_multilingual_commands name, aliases: [], **opts, &block
			LANGS.each do |lang|
				a = aliases.map { [:"#{_1}#{lang}", :"#{_1}#{lang.to_s[..1]}"] }.flatten.uniq
				command :"#{name}#{lang}", aliases: a, **opts do |event, *query|
					block.(lang, *query)
				end
			end
			command name, aliases:, **opts do |event, *query|
				id = event.user.id
				lang = DB.get_first_value 'select lang from user where id=?', id
				block.(lang&.to_sym || LANGS.first, *query)
			end
		end

		def gen_multilingual_dynamic_commands name, aliases: [], **opts, &block
			LANGS.each do |lang|
				a = aliases.map { [:"#{_1}#{lang}", :"#{_1}#{lang.to_s[..1]}"] }.flatten.uniq
				dynamic_command :"#{name}#{lang}", aliases: a, **opts do |event, session_token, *query|
					block.(lang, session_token, *query)
				end
			end
			dynamic_command name, aliases:, **opts do |event, session_token, *query|
				id = event.user.id
				lang = DB.get_first_value 'select lang from user where id=?', id
				block.(lang&.to_sym || LANGS.first, session_token, *query)
			end
		end

		TOKEN = ENV['LYRICAT_DISCORD_TOKEN'].freeze
		PREFIX = CONFIG[:prefix].freeze
		BOT = Discordrb::Commands::CommandBot.new token: TOKEN, prefix: PREFIX
		BOT.extend self
		BOT.instance_eval do

			description = <<~DESC.gsub ?\n, ?\s
				Display some useful info.
				Available items: `st`: what is and how to get session token;
				`mr`: how the MR is calculated;
				`dan`: intro to the Dan system.
			DESC
			usage = 'info [st|mr|dan]'
			command :info, description:, usage:, min_args: 1, max_args: 1 do |event, item|
				{
					st: <<~INFO.gsub(/\n+/) { _1.length == 1 ? ?\s : ?\n },
						**What is session token?**
						Session token is some text that Lyrica the game uses to authorize
						the HTTP requests to the server on behalf of you.
						It is also used by the server to identify you.
						It is different from your password in two ways:
						(1) it expires; (2) it identifies you.
						You should never share your session token publicly.
						
						**How to get my session token?**
						On Android, you can look at the file
						`/storage/emulated/0/Android/data/com.Rnova.lyrica/files/Parse.settings`.
						There is some text like `r:1234567890abcdef` in it.
						It is the session token.
						On iOS, there is no easy way to get your session token.
						You can use a tool called HTTP Toolkit
						to capture the HTTP requests made by Lyrica
						and look at the `X-Parse-Session-Token` header.
						For more info, see [here](https://httptoolkit.com/docs/guides/ios/).

						**How to invalidate my session token immediately?**
						If you accidentally shared your session token publicly,
						you need to invalidate it immediately.
						To do this, simply log out and log in again in Lyrica.

						**How to bind my session token?**
						Use the command `bind` to bind your session token.
						Use the command `help bind` to see how to use it.
					INFO
					mr: <<~INFO,
						月韵 (MR) 是 5.0 版本引入的用于衡量玩家水平的一个数。
						总 MR 的计算方式如下:
						- 计算所有谱面的单谱 MR, 并对每首歌曲的各难度谱面 (除 Frog Rappa 稀世以外) 的单谱 MR 取最大的一个作为该歌曲的单谱 MR。
						- 对所有 5.0 前的歌曲中单谱 MR 最高的 35 个 (旧 b35), 以及 5.0后的歌曲中单谱 MR 的最高的 15 个 (新 b15), 取平均值获得总 MR。
						单谱 MR 的计算公式:
						```
						S' = S / 10000
						M = {
							0, if S' < 50;
							max(0, d+1 - (98-S')/4), if 50 <= S' <= 98;
							d+2 - (100-S')/2, if S' >= 98
						}
						```
						其中S为分数，d为单谱定数
					INFO
					dan: <<~INFO,
						阳春白雪/阳春艺曲晋升之路(非官方)规则如下：
						1. 血量上限即为初始血量，挑战过程中任何时刻血量归0即为挑战失败。
						2. 扣血标准指每出现一个指定判定或以下则血量-1。
						3. 回复血量指当前晋升之路挑战中每通过一首歌所回复的血量(最后一首不回复)。
						4. 挑战关卡时，需要连续通过指定的四首歌曲，中间不能重试。若所挑战关卡有两组歌曲，则任选其一通过即算通过该关卡。
						5. 在结束四首晋升之路挑战歌曲之后算出(残余血量/血量上限x100%)得出的值与通过方式表进行对比，得出当前挑战的官位(例：41血完成拾肆段，血量残余82%，则为紫袍拾肆通过)。
						以下是通过方式：
						- 黄袍 x=100%
						- 紫袍 100%>x≥80%
						- 红袍 80%>x≥55%
						- 绿袍 55%>x≥30%
						- 青袍 30%>x>0%
						- 布衣(失败) x≤0%
					INFO
				}[item.to_sym] || 'Unknown item.'
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display basic information about a song.
				Can specify the song by song ID or fuzzy search using song name.
				Append `song` with one of `tw`, `cn`, `jp`, `eng` (such as `songcn`)
				to specify the language.
			DESC
			usage = 'song[lang] [song ID or fuzzy search query]'
			gen_multilingual_commands :song, description:, usage: do |lang, *query|
				song_id = Song.fuzzy_search lang, query.join(' ')
				return 'Not found.' unless song_id
				Song::LIB[song_id].info_inspect lang
			end

			description = <<~DESC.gsub ?\n, ?\s
				Randomly pick a song according to the difficulty.
				If no difficulty is specified, a random song will be picked.
				For specifying the difficulty, you can use one of the following:
				(1) A single integer `n`, which means the difficulty is in `[n,n+1)`;
				(2) A single number with decimal point `n`, which means the difficulty is exactly `n`;
				(3) Two numbers `n` and `m`, which means the difficulty is in `[n,m]`.
				Append `rand` with one of `tw`, `cn`, `jp`, `eng` (such as `randcn`)
				to specify the language.
			DESC
			usage = 'rand[lang] [difficulty]'
			gen_multilingual_commands :rand, aliases: %i[random], description:, usage:, max_args: 2 do |lang, *query|
				case query.size
				when 0
					min = 0
					max = Float::INFINITY
				when 1
					if query[0].like_int?
						min = query[0].to_i
						max = min + 1
					elsif query[0].like_float?
						min = query[0].to_f
						max = query[0].to_f + 0.1
					else
						return 'Invalid difficulty.'
					end
				when 2
					if query.any? { !_1.like_float? && !_1.like_int? }
						return 'Invalid difficulty.'
					end
					min = query[0].to_f
					max = query[1].to_f + 0.1
				end
				song_id = Song.random min, max
				return 'Not found.' unless song_id
				Song::LIB[song_id].info_inspect lang
			end

			description = <<~DESC.gsub ?\n, ?\s
				Bind your session token.
				A valid session token looks like `r:1234567890abcdef`.
				Use the command `info st` to see how to know your session token.
				**Do not send your session token publicly.
				Please DM me to use this command.**
			DESC
			usage = 'bind [session token]'
			command :bind, description:, usage:, min_args: 1, max_args: 1 do |event, session_token|
				event.message.delete if event.message.server
				id = event.user.id
				begin
					expiration = HeavyLifting.get_expiration_date session_token
				rescue HeavyLifting::BadUpstreamResponse
					if event.message.server
						return 'Bad session token. The original message is deleted for privacy reasons. Remember to bind in DM.'
					else
						return 'Bad session token.'
					end
				end
				if DB.execute('select id from user where id=?', id).empty?
					DB.execute 'insert into user values (?, ?, ?, ?)', id, session_token, (expiration.to_time.to_f*1000).round, LANGS.first
				else
					DB.execute 'update user set session_token=?, expiration=? where id=?', session_token, (expiration.to_time.to_f*1000).round, id
				end
				if event.message.server
					'Success! The original message is deleted for privacy reasons. Remember to bind in DM next time.'
				else
					'Success!'
				end
			end

			description = <<~DESC.gsub ?\n, ?\s
				Set the default language for the results of your commands.
				One of `tw`, `cn`, `jp`, or `eng`.
			DESC
			usage = 'lang [tw|cn|jp|eng]'
			command :lang, description:, usage:, min_args: 1, max_args: 1 do |event, lang|
				lang = 'eng' if lang == 'en'
				return 'Unknown language.' unless LANGS.include? lang.to_sym
				id = event.user.id
				if DB.execute('select id from user where id=?', id).empty?
					DB.execute 'insert into user values (?, ?, ?, ?)', id, nil, nil, lang
				else
					DB.execute 'update user set lang=? where id=?', lang, id
				end
				'Success!'
			end

			def b35 lang, session_token
				Song.best(35, Song::SORTED_OLD, session_token).map.with_index do |hash, i|
					song_id, diff_id, score, mr = hash.values_at :song_id, :diff_id, :score, :mr
					song = Song::LIB[song_id]
					diff = song.diff[diff_id]
					["#{i+1}. #{song.name lang}", "#{Song::DIFFS_NAME[diff_id][lang]} #{song.diff(lang, :in_game_and_abbr_precise, :id)[diff_id]}", score, mr]
				end
			end

			def b15 lang, session_token
				Song.best(15, Song::SORTED_NEW, session_token).map.with_index do |hash, i|
					song_id, diff_id, score, mr = hash.values_at :song_id, :diff_id, :score, :mr
					song = Song::LIB[song_id]
					diff = song.diff[diff_id]
					["#{i+1}. #{song.name lang}", "#{Song::DIFFS_NAME[diff_id][lang]} #{song.diff(lang, :in_game_and_abbr_precise, :id)[diff_id]}", score, mr]
				end
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display an order list of the top 35 scores in the songs before the latest major update.
				You need to use `bind` to bind your session token before using this command.
				Append `b35` with one of `tw`, `cn`, `jp`, `eng` (such as `b35cn`)
				to specify the language.
			DESC
			usage = 'b35[lang]'
			gen_multilingual_dynamic_commands :b35, description:, usage:, max_args: 0 do |lang, session_token|
				b35(lang, session_token).map { |line| line.join ?\t }.join ?\n
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display an order list of the top 15 scores in the songs after the latest major update.
				You need to use `bind` to bind your session token before using this command.
				Append `b15` with one of `tw`, `cn`, `jp`, `eng` (such as `b15cn`)
				to specify the language.
			DESC
			usage = 'b15[lang]'
			gen_multilingual_dynamic_commands :b15, description:, usage:, max_args: 0 do |lang, session_token|
				b15(lang, session_token).map { |line| line.join ?\t }.join ?\n
			end

			description = <<~DESC.gsub ?\n, ?\s
				Combine the results of `b35` and `b15`.
				You need to use `bind` to bind your session token before using this command.
				Append `b50` with one of `tw`, `cn`, `jp`, `eng` (such as `b50cn`)
				to specify the language.
			DESC
			usage = 'b50[lang]'
			gen_multilingual_dynamic_commands :b50, description:, usage:, max_args: 0 do |lang, session_token|
				b35 = b35(lang, session_token).map { |line| line.join ?\t }.join ?\n
				b15 = b15(lang, session_token).map { |line| line.join ?\t }.join ?\n
				b35 + "\n\n" + b15
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display your MR and b50.
				Use the optional argument to specify whether not to display b50.
				You need to use `bind` to bind your session token before using this command.
				Use `info mr` command to see how the MR is calculated.
				Append `mr` with one of `tw`, `cn`, `jp`, `eng` (such as `mrcn`)
				to specify the language.
			DESC
			usage = 'mr[lang] [whether to hide b50]'
			gen_multilingual_dynamic_commands :mr, description:, usage:, max_args: 1 do |lang, session_token, hide_b50|
				hide_b50 &&= %w[yes on true t y].include? hide_b50.downcase
				b35 = b35(lang, session_token)	
				b15 = b15(lang, session_token)
				b50 = [*b35, *b15]
				mr = (b50.sum { _1.last } / 50).round 8
				if hide_b50
					mr
				else
					<<~HEREDOC
						**MR**\t#{mr}
						**b35**\t(#{(b35.sum { _1.last } / 50).round 8})
						#{b35.map { |line| line.join ?\t }.join ?\n}
						**b15**\t(#{(b15.sum { _1.last } / 50).round 8})
						#{b15.map { |line| line.join ?\t }.join ?\n}
					HEREDOC
				end
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display the leaderboard of a chart.
				Does not support fuzzy search.
				Difficulty ID is: 1 for Easy, 2 for Normal, 3 for Hard, 4 for Master, 5 for Special.
				Append `leaderboard` with one of `tw`, `cn`, `jp`, `eng` (such as `leaderboardcn`)
				to specify the language.
			DESC
			usage = 'leaderboard[lang] [song ID] [difficulty ID]'
			gen_multilingual_commands :leaderboard, aliases: %i[lb], description:, usage:, min_args: 2, max_args: 2 do |lang, song_id, diff_id|
				return 'Bad song ID or difficulty ID.' unless song_id.like_int? && diff_id.like_int?
				song_id = song_id.to_i
				diff_id = diff_id.to_i
				song = Song::LIB[song_id]
				return 'No such chart.' unless song&.diff[diff_id]
				begin
					leaderboard = HeavyLifting.get_leaderboard SESSION_TOKEN, song_id, diff_id
				rescue HeavyLifting::BadUpstreamResponse
					return "There is a problem in retrieving the leaderboard. Please contact <@#{MAINTAINER_ID}>."
				end
				text = leaderboard.map do |hash|
					score, nickname, rank = hash.values_at :score, :nickname, :rank
					"#{rank}. #{nickname}\t#{score}"
				end.join ?\n
				"#{song.name lang}\t#{Song::DIFFS_NAME[diff_id][lang]}\n#{text}"
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display the month leaderboard of a chart in the current month.
				Does not support fuzzy search.
				Difficulty ID is: 1 for Easy, 2 for Normal, 3 for Hard, 4 for Master, 5 for Special.
				Append `monthleaderboard` with one of `tw`, `cn`, `jp`, `eng` (such as `monthleaderboardcn`)
				to specify the language.
			DESC
			usage = 'monthleaderboard[lang] [song ID] [difficulty ID]'
			gen_multilingual_commands :monthleaderboard, aliases: %i[mlb], description:, usage:, min_args: 2, max_args: 2 do |lang, song_id, diff_id|
				return 'Bad song ID or difficulty ID.' unless song_id.like_int? && diff_id.like_int?
				song_id = song_id.to_i
				diff_id = diff_id.to_i
				song = Song::LIB[song_id]
				return 'No such chart.' unless song&.diff[diff_id]
				begin
					leaderboard = HeavyLifting.get_month_leaderboard SESSION_TOKEN, song_id, diff_id
				rescue HeavyLifting::BadUpstreamResponse
					return "There is a problem in retrieving the leaderboard. Please contact <@#{MAINTAINER_ID}>."
				end
				text = leaderboard.map do |hash|
					score, nickname, rank = hash.values_at :score, :nickname, :rank
					"#{rank}. #{nickname}\t#{score}"
				end.join ?\n
				"#{song.name lang}\t#{Song::DIFFS_NAME[diff_id][lang]}\n#{text}"
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display the score and rank of charts of a song.
				Does not support fuzzy search.
				You need to use `bind` to bind your session token before using this command.
				Append `score` with one of `tw`, `cn`, `jp`, `eng` (such as `scorecn`)
				to specify the language.
			DESC
			usage = 'score[lang] [song ID]'
			gen_multilingual_dynamic_commands :score, aliases: %i[rank], description:, usage:, min_args: 1, max_args: 1 do |lang, session_token, song_id|
				return 'Bad song ID.' unless song_id.like_int?
				song_id = song_id.to_i
				song = Song::LIB[song_id]
				return 'No such song.' unless song
				result = song.name(lang) + ?\n
				scores = Concurrent::Hash.new
				ranks = Concurrent::Hash.new
				song.diff.map do |diff_id, diff|
					Thread.new do
						leaderboard = HeavyLifting.get_my_leaderboard session_token, song_id, diff_id
						score, rank = leaderboard.values_at :score, :rank
						scores[diff_id] = score
						ranks[diff_id] = rank
					end.tap { _1.abort_on_exception = true }
				end.each &:join
				song.diff(lang, :in_game_and_abbr_precise).each do |diff_id, diff|
					result += "- #{Song::DIFFS_NAME[diff_id][lang]} #{diff}\t#{scores[diff_id]}\t#{ranks[diff_id]}\n"
				end
				result[...-1]
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display the score and rank of charts of a song in the current month.
				Does not support fuzzy search.
				You need to use `bind` to bind your session token before using this command.
				Append `monthscore` with one of `tw`, `cn`, `jp`, `eng` (such as `monthscorecn`)
				to specify the language.
			DESC
			usage = 'monthscore[lang] [song ID]'
			gen_multilingual_dynamic_commands :monthscore, aliases: %i[monthrank mscore mrank], description:, usage:, min_args: 1, max_args: 1 do |lang, session_token, song_id|
				return 'Bad song ID.' unless song_id.like_int?
				song_id = song_id.to_i
				song = Song::LIB[song_id]
				return 'No such song.' unless song
				result = song.name(lang) + ?\n
				scores = Concurrent::Hash.new
				ranks = Concurrent::Hash.new
				song.diff.map do |diff_id, diff|
					Thread.new do
						leaderboard = HeavyLifting.get_my_month_leaderboard session_token, song_id, diff_id
						score, rank = leaderboard.values_at :score, :rank
						scores[diff_id] = score
						ranks[diff_id] = rank
					end.tap { _1.abort_on_exception = true }
				end.each &:join
				song.diff(lang, :in_game_and_abbr_precise).each do |diff_id, diff|
					result += "- #{Song::DIFFS_NAME[diff_id][lang]} #{diff}\t#{scores[diff_id]}\t#{ranks[diff_id]}\n"
				end
				result[...-1]
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display the lyrics of a song.
				Does not support fuzzy search.
			DESC
			usage = 'lyrics [song ID]'
			command :lyrics, description:, usage: do |event, song_id|
				return 'Bad song ID.' unless song_id.like_int?
				song_id = song_id.to_i
				song = Song::LIB[song_id]
				return 'No such song.' unless song
				result = [song.lyrics, song.lyrics_b].compact.join "\n\n"
				result = 'No lyrics.' if result.empty?
				result
			end

		end

	end
end
