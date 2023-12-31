# frozen_string_literal: true

module Lyricat
	class Singer
		attr_reader :index, :weblink, :fblink, :etclink, :songs

		def initialize hash
			@index = hash[:index][1..].to_i
			@weblink = hash[:weblink]
			@fblink = hash[:fblink]
			@etclink = hash[:etclink]
			@info = {tw: hash[:info], cn: hash[:infocn], jp: hash[:infojp], eng: hash[:infoeng]}
			@name = {tw: hash[:singer], cn: hash[:singercn], jp: hash[:singerjp], eng: hash[:singereng]}
			@name.transform_values! { _1.gsub ?|, ?\s }
			@info.transform_values! { _1.gsub ?|, ?\n }
			@songs = []
			@ascii_name = @name.transform_values { AnyAscii.transliterate _1 }
		end

		def info lang = LANGS.first
			@info[lang]
		end

		def name lang = LANGS.first
			@name[lang]
		end

		def match_roman1 query, strong, lang = nil
			query = query.gsub(/\s/, '').downcase
			meth = strong ? :== : :include?
			values = lang ? [@ascii_name[lang]] : @ascii_name.values
			values.any? { |roman| roman.gsub(/\s/, '').downcase.__send__ meth, query }
		end

		def match_roman2 query, strong, lang = nil
			query = query.gsub(/\s/, '').downcase
			meth = strong ? :== : :include?
			values = lang ? [@ascii_name[lang]] : @ascii_name.values
			return true if values.any? { |roman| roman.upper_letters.__send__ meth, query }
			return true if values.any? { |roman| (words = roman.split).length > 1 && words.map { _1[0] }.join.downcase.__send__(meth, query) }
			false
		end

		def match_name query, strong, lang = nil
			query = query.strip.downcase
			meth = strong ? :== : :include?
			values = lang ? [@name[lang]] : @name.values
			values.any? { _1.strip.__send__ meth, query }
		end

		def info_inspect lang = LANGS.first
			<<~END
				**ID**\t#{@index}
				**Name**\t#{@name[lang]}
				**Info**
				#{@info[lang]}
				**Web link**\t#{@weblink}
				**Facebook link**\t#{@fblink}
				**Other link**\t#{@etclink}
				**Songs**
				#{@songs.map { "- #{Song::LIB[_1].name lang}" }.join ?\n}
			END
		end

		class << self
			def add_singer hash, lib
				return unless hash[:index] =~ /\A>\d+\z/
				lib[hash[:index][1..].to_i] = new(hash)
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
		end
		
		LIB = Lyricat.sheet(:singer).each_with_object({}, &method(:add_singer)).freeze
	end
end
