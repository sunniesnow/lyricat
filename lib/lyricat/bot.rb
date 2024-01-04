# frozen_string_literal: true

module Lyricat
	class Bot < Discordrb::Commands::CommandBot

		SESSION_TOKEN = ENV['LYRICAT_STATIC_SESSION_TOKEN'].freeze
		raise 'LYRICAT_STATIC_SESSION_TOKEN not set' unless SESSION_TOKEN

		DB = SQLite3::Database.new File.join DATA_DIR, 'data.db'
		if DB.execute('select name from sqlite_master where type="table" and name="user"').empty?
			DB.execute 'create table user (id bigint primary key, session_token varchar(50), expiration bigint, lang varchar(10), song_aliases text)'
		end
		DB.type_translation = true

		class << self
			def ensure_user id
				return if has_user? id
				DB.execute 'insert into user values (?, ?, ?, ?, ?)', id, nil, nil, LANGS.first.to_s, '{}'
			end

			def has_user? id
				!DB.execute('select id from user where id=?', id).empty?
			end

			def update_user id, **hash
				hash.transform_keys! { _1.to_s }
				ensure_user id
				DB.execute "update user set #{hash.keys.map { "#{_1}=?" }.join ?,} where id=?", *hash.values, id
			end

			def get_user_property id, property, default = nil
				row = DB.get_first_row "select #{property} from user where id=?", id
				row ? row.first : default
			end

			def run
				BOT.run
			end
		end

		MAX_TYPING_TIME = CONFIG[:max_typing_time] || 30

		EXPIRATION_MARGIN = CONFIG[:expiration_margin]
		MAINTAINER_ID = ENV['LYRICAT_DISCORD_MAINTAINER_ID'] || 0

		def dynamic_command name, **opts, &block
			command name, **opts do |event, *query|
				id = event.user.id
				next '*Bind your session token first.*' unless session_token = Bot.get_user_property(id, :session_token)
				expiration = Bot.get_user_property id, :expiration, Float::INFINITY
				next '*Session token expired. Please rebind.*' if expiration < Time.now.to_f * 1000 + EXPIRATION_MARGIN
				begin
					block.(event, session_token, *query)
				rescue HeavyLifting::BadUpstreamResponse => e
					puts e.backtrace
					'*Bad upstream response. Try binding a new session token?*'
				end
			end
		end

		def command *args, **opts, &block
			super *args, **opts do |event, *query|
				typing_thread = Thread.new do
					(MAX_TYPING_TIME / 4).floor.times do
						event.channel.start_typing
						sleep 4
					end
				end
				try_reply event.message, block.(event, *query)
				typing_thread.kill
				nil
			end
		end

		def try_reply message, text
			if message.channel.load_message message.id
				message.reply! text, mention_user: true
			else
				deliminator = text.include?(?\n) ? ?\n : ?\s
				message.respond "<@#{message.user.id}>#{deliminator}#{text}"
			end
		end

		def gen_multilingual_commands name, aliases: [], **opts, &block
			command name, aliases:, **opts do |event, *query|
				id = event.user.id
				lang = Bot.get_user_property id, :lang, LANGS.first
				block.(event, lang.to_sym, *query)
			end
			LANGS.each do |lang|
				a = [name, *aliases].map { [:"#{_1}#{lang}", :"#{_1}#{lang.to_s[..1]}"] }.flatten.uniq
				command a[0], aliases: a[1..], **opts do |event, *query|
					block.(event, lang, *query)
				end
			end
		end

		def gen_multilingual_dynamic_commands name, aliases: [], **opts, &block
			dynamic_command name, aliases:, **opts do |event, session_token, *query|
				id = event.user.id
				lang = Bot.get_user_property id, :lang, LANGS.first
				block.(event, lang.to_sym, session_token, *query)
			end
			LANGS.each do |lang|
				a = [name, *aliases].map { [:"#{_1}#{lang}", :"#{_1}#{lang.to_s[..1]}"] }.flatten.uniq
				dynamic_command a[0], aliases: a[1..], **opts do |event, session_token, *query|
					block.(event, lang, session_token, *query)
				end
			end
		end

		TOKEN = ENV['LYRICAT_DISCORD_TOKEN'].freeze
		PREFIX = CONFIG[:prefix].freeze
		BOT = new token: TOKEN, prefix: PREFIX, help_command: false
		BOT.instance_eval do

			command :help, max_args: 1, description: 'Shows a list of all the commands available or displays help for a specific command.', usage: 'help [command name]' do |event, command_name|
				if command_name
					command = @commands[command_name.to_sym]
					if command.is_a?(Discordrb::Commands::CommandAlias)
						command = command.aliased_command
						command_name = command.name
					end
					next "*Unknown command.*" unless command

					desc = command.attributes[:description] || '*No description available.*'
					usage = command.attributes[:usage]
					parameters = command.attributes[:parameters]
					result = "**`#{command_name}`**\t#{desc}"
					aliases = command_aliases(command_name.to_sym)
					unless aliases.empty?
						result += "\n**Aliases**\t"
						result += aliases.map { |a| "`#{a.name}`" }.join(', ')
					end
					result += "\n**Usage**\t`#{usage}`" if usage
					if parameters
						result += "\n**Accepted Parameters**\n```"
						parameters.each { |p| result += "\n- #{p}" }
						result += '```'
					end
					result
				else
					available_commands = @commands.values.reject do |c|
						c.is_a?(Discordrb::Commands::CommandAlias) || !c.attributes[:help_available] || !required_roles?(event.user, c.attributes[:required_roles]) || !allowed_roles?(event.user, c.attributes[:allowed_roles]) || !required_permissions?(event.user, c.attributes[:required_permissions], event.channel)
					end.sort_by &:name
					case available_commands.length
					when 0..5
						available_commands.reduce "**List of commands**\n" do |memo, c|
							memo + "**`#{c.name}`**: #{c.attributes[:description] || '*No description available*'}\n"
						end
					else
						(available_commands.reduce "**List of commands**\n" do |memo, c|
							memo + "`#{c.name}`, "
						end)[0..-3]
					end
				end
			end

			ready do |event|
				update_status 'online', "#{PREFIX}help", nil
			end

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
						For the Chinese version of Lyrica, the file is
						`/storage/emulated/0/Android/data/com.wexgames.ycbx/files/Parse.settings`
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
						**Calculation of MR**
						Calculate the single-chart MR for each chart, \
						and then for each song, among all its charts (accept Frog Rappa Special), \
						pick the one with the highest single-chart MR as the single-song MR of the song. \
						Among songs before 5.0, pick 35 ones (called **b35**) \
						with the highest single-song MRs. \
						Among songs after 5.0, pick 15 ones (called **b15**) \
						with the highest single-song MRs. \
						Then, the average single-song MRs of all the 50 songs (called **b50**) \
						is the total MR of the player.
						The calculation of the single-chart MR is as follows:
						```
						S' = S / 10000
						M = {
							0, if S' < 50;
							max(0, d+1 - (98-S')/4), if 50 <= S' <= 98;
							d+2 - (100-S')/2, if S' >= 98
						}
						```where `S` is the score, and `d` is the difficulty.
					INFO
					dan: <<~INFO,
						**Dan rules**
						Challenge fails if HP reaches 0 during the challenge. \
						The HP reduces by 1 when one judgement that is or is below the hit-by judgement apppears. \
						The HP heals at the end of each level within the dan course (except the last one). \
						You need to pass four songs in a row without retrying to pass a dan course. \
						If there are two sets of songs in a dan course, you can choose either one to pass. \
						Calculate the ratio `x` of the remaining HP to the initial HP, and compare it with the following table to get your dan rank:
						- Yellow: `x = 100%`;
						- Purple: `100% > x >= 80%`;
						- Red: `80% > x >= 55%`;
						- Green: `55% > x >= 30%`;
						- Blue: `30% > x > 0%`;
						- White (fail): `x <= 0%`.
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
			gen_multilingual_commands :song, description:, usage: do |event, lang, *query|
				query = query.join ' '
				song_id = JSON.parse(Bot.get_user_property event.user.id, :song_aliases, '{}')[query]
				song_id ||= Song.fuzzy_search lang, query
				next '*Not found.*' unless song_id
				Song::LIB[song_id].info_inspect lang
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display basic information about a singer.
				Can specify the singer by singer ID or fuzzy search using singer name.
				Append `singer` with one of `tw`, `cn`, `jp`, `eng` (such as `singercn`)
				to specify the language.
			DESC
			usage = 'singer[lang] [singer ID or fuzzy search query]'
			gen_multilingual_commands :singer, description:, usage: do |event, lang, *query|
				singer_id = Singer.fuzzy_search lang, query.join(' ')
				next '*Not found.*' unless singer_id
				Singer::LIB[singer_id].info_inspect lang
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
			gen_multilingual_commands :rand, aliases: %i[random], description:, usage:, max_args: 2 do |event, lang, *query|
				songs_id = Song.select_songs_by_difficulty_query *query
				next '*Invalid difficulty.*' unless songs_id
				song_id = songs_id.sample
				next '*Not found.*' unless song_id
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
						next '*Bad session token. The original message is deleted for privacy reasons. Remember to bind in DM.*'
					else
						next '*Bad session token.*'
					end
				end
				Bot.update_user id, session_token: session_token, expiration: (expiration.to_time.to_f*1000).round
				if event.message.server
					'*Successfully binded your session token! The original message is deleted for privacy reasons. Remember to bind in DM next time.*'
				else
					'*Success!*'
				end
			end

			description = <<~DESC.gsub ?\n, ?\s
				Unbind your session token.
				Your session token will be deleted from the database of the bot.
				You will have to bind your session token again to use the commands that require it.
			DESC
			usage = 'unbind'
			command :unbind, description:, usage:, max_args: 0 do |event|
				id = event.user.id
				next '*You have not bound your session token yet.*' unless Bot.get_user_property id, :session_token
				Bot.update_user id, session_token: nil, expiration: nil
				'*Success!*'
			end

			description = <<~DESC.gsub ?\n, ?\s
				Set the default language for the results of your commands.
				One of `tw`, `cn`, `jp`, or `eng`.
			DESC
			usage = 'lang [tw|cn|jp|eng]'
			command :lang, description:, usage:, min_args: 1, max_args: 1 do |event, lang|
				lang = 'eng' if lang == 'en'
				next '*Unknown language.*' unless LANGS.include? lang.to_sym
				Bot.update_user event.user.id, lang: lang
				'*Success!*'
			end

			description = <<~DESC.gsub ?\n, ?\s
				Sets an alias for a song.
				The alias can be used to search for the song when using the `song` command.
				Other people cannot use the alias you set unless they set the same alias.
				You can set multiple aliases for a song.
				Use `listaliases` to see all your aliases.
				Use `deletealias` to delete an alias.
			DESC
			usage = 'alias [song ID] [alias]'
			command :alias, description:, usage:, min_args: 2, max_args: 2 do |event, song_id, *alias_|
				next '*Bada song ID.*' unless song_id.like_int?
				next '*Alias cannot be empty.*' if alias_.empty?
				song_id = song_id.to_i
				next '*No such song.*' unless Song::LIB[song_id]
				aliases = JSON.parse Bot.get_user_property(event.user.id, :song_aliases, '{}'), symbolize_names: true
				aliases[alias_.join ' '] = song_id
				aliases = aliases.sort_by { _2 }.to_h
				Bot.update_user event.user.id, song_aliases: aliases.to_json
				'*Success!*'
			end

			description = <<~DESC.gsub ?\n, ?\s
				List all your aliases.
				You can use the aliases to search for the song when using the `song` command.
				Other people cannot use the aliases you set unless they set the same aliases.
				Append `listaliases` with one of `tw`, `cn`, `jp`, `eng` (such as `listaliasescn`)
				to specify the language.
				Use `alias` to set an alias.
				Use `deletealias` to delete an alias.
			DESC
			usage = 'listaliases'
			gen_multilingual_commands :listaliases, aliases: %i[lalias laliases listalias], description:, usage:, max_args: 0 do |event, lang|
				aliases = JSON.parse Bot.get_user_property(event.user.id, :song_aliases, '{}'), symbolize_names: true
				next '*Nothing here...*' if aliases.empty?
				aliases.transform_values! { "#{_1} (#{Song::LIB[_1].name lang}): "}
				aliases.map { |alias_, value| "- #{value}#{alias_}" }.join ?\n
			end

			description = <<~DESC.gsub ?\n, ?\s
				Delete an alias.
				Use `alias` to set an alias.
				Use `listaliases` to see all your aliases.
			DESC
			usage = 'deletealias [alias]'
			command :deletealias, aliases: %i[dalias rmalias delalias], description:, usage:, min_args: 1 do |event, *alias_|
				aliases = JSON.parse Bot.get_user_property event.user.id, :song_aliases, '{}'
				if aliases.delete alias_.join(' ')
					Bot.update_user event.user.id, song_aliases: aliases.to_json
					'*Success!*'
				else
					'*No such alias.*'
				end
			end

			def b35 lang, session_token
				Song.best(35, Song::SORTED_OLD, session_token).map.with_index do |hash, i|
					song_id, diff_id, score, mr = hash.values_at :song_id, :diff_id, :score, :mr
					song = Song::LIB[song_id]
					diff = song.diff[diff_id]
					["#{i+1}. #{song.name lang}", "#{Song.diff_name_in_game diff_id, lang} #{song.diff(lang, :in_game_and_abbr_precise, :id)[diff_id]}", score, mr]
				end
			end

			def b15 lang, session_token
				Song.best(15, Song::SORTED_NEW, session_token).map.with_index do |hash, i|
					song_id, diff_id, score, mr = hash.values_at :song_id, :diff_id, :score, :mr
					song = Song::LIB[song_id]
					diff = song.diff[diff_id]
					["#{i+1}. #{song.name lang}", "#{Song.diff_name_in_game diff_id, lang} #{song.diff(lang, :in_game_and_abbr_precise, :id)[diff_id]}", score, mr]
				end
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display an order list of the top 35 scores in the songs before the latest major update.
				You need to use `bind` to bind your session token before using this command.
				Append `b35` with one of `tw`, `cn`, `jp`, `eng` (such as `b35cn`)
				to specify the language.
			DESC
			usage = 'b35[lang]'
			gen_multilingual_dynamic_commands :b35, description:, usage:, max_args: 0 do |event, lang, session_token|
				result = b35(lang, session_token).map { |line| line.join ?\t }.join ?\n
				result = 'Nothing here...' if result.empty?
				result
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display an order list of the top 15 scores in the songs after the latest major update.
				You need to use `bind` to bind your session token before using this command.
				Append `b15` with one of `tw`, `cn`, `jp`, `eng` (such as `b15cn`)
				to specify the language.
			DESC
			usage = 'b15[lang]'
			gen_multilingual_dynamic_commands :b15, description:, usage:, max_args: 0 do |event, lang, session_token|
				result = b15(lang, session_token).map { |line| line.join ?\t }.join ?\n
				result = 'Nothing here...' if result.empty?
				result
			end

			description = <<~DESC.gsub ?\n, ?\s
				Combine the results of `b35` and `b15`.
				You need to use `bind` to bind your session token before using this command.
				Append `b50` with one of `tw`, `cn`, `jp`, `eng` (such as `b50cn`)
				to specify the language.
			DESC
			usage = 'b50[lang]'
			gen_multilingual_dynamic_commands :b50, description:, usage:, max_args: 0 do |event, lang, session_token|
				b35 = b35(lang, session_token).map { |line| line.join ?\t }.join ?\n
				b15 = b15(lang, session_token).map { |line| line.join ?\t }.join ?\n
				result = [b35, b15].delete_if(&:empty?).join "\n\n"
				result = 'Nothing here...' if result.empty?
				result
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
			gen_multilingual_dynamic_commands :mr, description:, usage:, max_args: 1 do |event, lang, session_token, hide_b50|
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
						#{(b35.map { |line| line.join ?\t }.join ?\n).then { _1.empty? ? 'Nothing here...' : _1 }}
						**b15**\t(#{(b15.sum { _1.last } / 50).round 8})
						#{(b15.map { |line| line.join ?\t }.join ?\n).then { _1.empty? ? 'Nothing here...' : _1 }}
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
			gen_multilingual_commands :leaderboard, aliases: %i[lb], description:, usage:, min_args: 2, max_args: 2 do |event, lang, song_id, diff_id|
				next '*Bad song ID or difficulty ID.*' unless song_id.like_int? && diff_id.like_int?
				song_id = song_id.to_i
				diff_id = diff_id.to_i
				song = Song::LIB[song_id]
				next '*No such chart.*' unless song&.diff[diff_id]
				begin
					leaderboard = HeavyLifting.get_leaderboard SESSION_TOKEN, song_id, diff_id
				rescue HeavyLifting::BadUpstreamResponse
					next "*There is a problem in retrieving the leaderboard. Please contact <@#{MAINTAINER_ID}>.*"
				end
				text = leaderboard.map do |hash|
					score, nickname, rank = hash.values_at :score, :nickname, :rank
					"#{rank}. #{nickname}\t#{score}"
				end.join ?\n
				result = "#{song.name lang}\t#{Song.diff_name_in_game diff_id, lang}\n#{text}"
				result += '*No one is here...*' if text.empty?
				result
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display the month leaderboard of a chart in the current month.
				Does not support fuzzy search.
				Difficulty ID is: 1 for Easy, 2 for Normal, 3 for Hard, 4 for Master, 5 for Special.
				Append `monthleaderboard` with one of `tw`, `cn`, `jp`, `eng` (such as `monthleaderboardcn`)
				to specify the language.
			DESC
			usage = 'monthleaderboard[lang] [song ID] [difficulty ID]'
			gen_multilingual_commands :monthleaderboard, aliases: %i[mlb], description:, usage:, min_args: 2, max_args: 2 do |event, lang, song_id, diff_id|
				next '*Bad song ID or difficulty ID.*' unless song_id.like_int? && diff_id.like_int?
				song_id = song_id.to_i
				diff_id = diff_id.to_i
				song = Song::LIB[song_id]
				next '*No such chart.*' unless song&.diff[diff_id]
				begin
					leaderboard = HeavyLifting.get_month_leaderboard SESSION_TOKEN, song_id, diff_id
				rescue HeavyLifting::BadUpstreamResponse
					next "*There is a problem in retrieving the leaderboard. Please contact <@#{MAINTAINER_ID}>.*"
				end
				text = leaderboard.map do |hash|
					score, nickname, rank = hash.values_at :score, :nickname, :rank
					"#{rank}. #{nickname}\t#{score}"
				end.join ?\n
				result = "#{song.name lang}\t#{Song.diff_name_in_game diff_id, lang}\n#{text}"
				result += '*No one is here...*' if text.empty?
				result
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display the score and rank of charts of a song.
				Does not support fuzzy search.
				You need to use `bind` to bind your session token before using this command.
				Append `score` with one of `tw`, `cn`, `jp`, `eng` (such as `scorecn`)
				to specify the language.
			DESC
			usage = 'score[lang] [song ID]'
			gen_multilingual_dynamic_commands :score, aliases: %i[rank], description:, usage:, min_args: 1, max_args: 1 do |event, lang, session_token, song_id|
				next '*Bad song ID.*' unless song_id.like_int?
				song_id = song_id.to_i
				song = Song::LIB[song_id]
				next '*No such song.*' unless song
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
					result += "- #{Song.diff_name_in_game diff_id, lang} #{diff}\t#{scores[diff_id]}\t#{ranks[diff_id]}\n"
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
			gen_multilingual_dynamic_commands :monthscore, aliases: %i[monthrank mscore mrank], description:, usage:, min_args: 1, max_args: 1 do |event, lang, session_token, song_id|
				next '*Bad song ID.*' unless song_id.like_int?
				song_id = song_id.to_i
				song = Song::LIB[song_id]
				next '*No such song.*' unless song
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
					result += "- #{Song.diff_name_in_game diff_id, lang} #{diff}\t#{scores[diff_id]}\t#{ranks[diff_id]}\n"
				end
				result[...-1]
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display the lyrics of a song.
				Does not support fuzzy search.
				Append `lyrics` with one of `tw`, `cn`, `jp`, `eng` (such as `lyricscn`)
				to specify the language.
			DESC
			usage = 'lyrics[lang] [song ID]'
			gen_multilingual_commands :lyrics, description:, usage: do |event, lang, song_id|
				next '*Bad song ID.*' unless song_id.like_int?
				song_id = song_id.to_i
				song = Song::LIB[song_id]
				next '*No such song.*' unless song
				result = song.lyrics lang
				result = '*No lyrics.*' if !result || result.empty?
				result
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display analysis of a song.
				Does not support fuzzy search.
				Append `analysis` with one of `tw`, `cn`, `jp`, `eng` (such as `analysiscn`)
				to specify the language.
			DESC
			usage = 'anal[lang] [song ID]'
			gen_multilingual_commands :anal, aliases: %i[analysis lyricsinfo], description:, usage: do |event, lang, song_id|
				next '*Bad song ID.*' unless song_id.like_int?
				song_id = song_id.to_i
				song = Song::LIB[song_id]
				next '*No such song.*' unless song
				result = song.lyrics_info lang
				result = '*No analysis.*' if !result || result.empty?
				result
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display user info,
				including username, creation time, and nickname.
				You need to use `bind` to bind your session token before using this command.
			DESC
			usage = 'me'
			dynamic_command :me, aliases: %i[user account], description:, usage:, max_args: 0 do |event, session_token|
				user = HeavyLifting.get_user session_token
				"**Username**\t#{user[:username]}\n**Created at**\t#{user[:created_at]}\n**Nickname**\t#{user[:nickname]}"
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display basic information about a dan.
				The dan ID ranges from 1 to 18.
				Including the levels, hit points, healing, and hit-by judgement.
				For an introduction to the Dan system and Dan rules, use `info dan`.
				Append `dan` with one of `tw`, `cn`, `jp`, `eng` (such as `dancn`)
				to specify the language.
			DESC
			usage = 'dan[lang] [dan ID]'
			gen_multilingual_commands :dan, description:, usage:, min_args: 1, max_args: 1 do |event, lang, dan_id|
				next '*Bad dan ID.*' unless dan_id.like_int?
				dan_id = dan_id.to_i
				dan = Dan::LIB[dan_id]
				next '*No such dan.*' unless dan
				dan.info_inspect lang
			end

			description = <<~DESC.gsub ?\n, ?\s
				Display a list of songs according to the difficulties.
				For specifying the difficulty, you can use one of the following:
				(1) A single integer `n`, which means the difficulty is in `[n,n+1)`;
				(2) A single number with decimal point `n`, which means the difficulty is exactly `n`;
				(3) Two numbers `n` and `m`, which means the difficulty is in `[n,m]`.
				Append `listsongs` with one of `tw`, `cn`, `jp`, `eng` (such as `scorecn`)
				to specify the language.
			DESC
			usage = 'listsongs[lang] [difficulty]'
			gen_multilingual_commands :listsongs, aliases: %i[ls lsong listsong rt], description:, usage:, max_args: 2 do |event, lang, *query|
				min, max = Song.parse_difficulty_query *query
				next '*Invalid difficulty.*' unless min && max
				link = event.message.link
				pm = false
				r = (min...max).step(0.1).reverse_each.with_object String.new do |diff, result|
					middle_result = Song.select_charts_by_difficulty(diff).with_object String.new do |(song_id, diff_id), s|
						song = Song::LIB[song_id]
						s.concat "- #{song.name lang}\t#{Song.diff_name_in_game diff_id, lang}\n"
					end
					unless middle_result.empty?
						middle_result = "**#{Song.diff_in_game_and_abbr_precise diff, lang}**\n" + middle_result
						if result.length + middle_result.length + link.length + 1 > 2000
							if event.channel.pm?
								try_reply event.message, result
							else
								pm = true
								event.user.pm "#{link}\n#{result}"
							end
							result.replace middle_result
						else
							result.concat middle_result
						end
					end
				end
				r.empty? ? '*Not found.*' : pm ? event.user.pm("#{link}\n#{r}") && '*Sent to your DM.*' : r
			end
		end

	end
end
