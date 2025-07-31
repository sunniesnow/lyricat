module Lyricat
	class Dan

		lang_sheet = Lyricat.sheet :language
		begin item = lang_sheet.shift end until item[:index] == '#' && item[:tw] == 1
		JUDGEMENT_NAMES = (0..3).map { [_1, lang_sheet[14+_1]] }.to_h.freeze

		attr_reader :index, :levels, :health, :heal, :judgement

		def initialize hash
			@index = hash[:index]
			@levels = hash[:levels]
			@health = hash[:health]
			@heal = hash[:heal]
			@judgement = hash[:judgement]
		end

		def info_inspect lang
			levels = @levels.map do |bunch|
				bunch.map.with_index do |level, i|
					song = Song::LIB[level[:song_id]]
					diff_id = level[:diff_id]
					diff_name = Song::DIFFS_NAME[diff_id][lang]
					diff = song.diff(lang, :in_game_and_abbr_precise)[diff_id]
					"#{i+1}. #{song.name lang}\t#{diff_name} #{diff}"
				end.join ?\n
			end
			<<~END
				**Dan**\t#{@index}
				**Levels**
				#{levels.join "\nOR\n"}
				**Hit points**\t#{@health}
				**Healing**\t#{@heal}
				**Hit by**\t#{JUDGEMENT_NAMES[@judgement][lang]}
			END
		end

		LIB = YAML.load_file(File.join(Lyricat::DATA_DIR, ENV['LYRICAT_DAN'] || 'dan.yml'), symbolize_names: true).map { [_1[:index], new(_1)] }.to_h.freeze
	end
end
