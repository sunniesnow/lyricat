# frozen_string_literal: true

require 'yaml'
require 'net/http'
require 'json'
require 'date'

require 'discordrb'
require 'sqlite3'
require 'concurrent'
require 'any_ascii'

require 'patches'

require 'lyricat/version'

module Lyricat

	DIFF = (1..5).map { [_1, %i[_ diffe diffn diffh diffm diffsp][_1]] }.to_h.freeze
	DATA_DIR = ENV['LYRICAT_DATA_DIR'] || File.join(__dir__, '..', 'data')
	RES_DIR = ENV['LYRICAT_RES_DIR'] || File.join(__dir__, '..', 'res')
	CONFIG = YAML.load_file(File.join(DATA_DIR, 'config.yml'), symbolize_names: true).freeze
	LANGS = %i[tw cn jp eng].freeze

	def self.res symbol, *args
		path = File.join RES_DIR, sprintf(CONFIG[:res][symbol], *args)
		File.exist?(path) ? File.read(path) : nil
	end

	def self.sheet symbol
		base_path = ENV['LYRICAT_RES_PATH'] || __dir__
		YAML.load_file(File.join(RES_DIR, CONFIG[:res][symbol]), symbolize_names: true)[:MonoBehaviour][:dataArray]
	end

end

require 'lyricat/heavylifting'
require 'lyricat/song'
require 'lyricat/bot'
