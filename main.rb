#!/usr/bin/env ruby

$:<< File.join(__dir__, 'lib')
require 'lyricat'

Lyricat::Bot.run
