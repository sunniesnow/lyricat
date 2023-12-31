# frozen_string_literal: true

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

	def like_float?
		/\A\d+(\.\d+)?\z/ === self
	end

	def upper_letters
		chars.filter { _1 =~ /[A-Z]/ }.join.downcase
	end
end
