#!/usr/bin/env ruby
# frozen_string_literal: true

$:<< File.join(__dir__, 'lib')
require 'lyricat'

Lyricat::Bot.run
