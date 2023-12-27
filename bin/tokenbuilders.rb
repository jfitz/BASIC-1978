# frozen_string_literal: true

# abstract class
class AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    # configuration
    @default_enabled = default_enabled
    @trigger_tokens = trigger_tokens
    # state
    @enabled = @default_enabled
    # properties
    @token = ''
    @count = 0
  end

  def see_keyword(token, seen_keywords)
    return if token.whitespace?

    if seen_keywords == @trigger_tokens
      @enabled = !@default_enabled
    end
  end

  def reset
    @enabled = @default_enabled
  end

  def count
    @token.size
  end
end

# accept any characters
class InvalidTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    @token += text.empty? ? '' : text[0]
  end

  def tokens
    [InvalidToken.new(@token)]
  end
end

# statement separator characters
class StatementSeparatorTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled

    return if text.empty?

    statement_seps = [':', '\\']

    @token = text[0] if statement_seps.include?(text[0])
  end

  def tokens
    [StatementSeparatorToken.new(@token)]
  end
end

# accept characters to match item in list
class ListTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens, legals, class_name)
    super(default_enabled, trigger_tokens)

    @legals = legals
    @class = class_name
    @count = 0
  end

  def count
    @count
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    best_candidate = ''
    best_count = 0

    if !text.empty? && text[0] != ' '
      candidate = ''
      i = 0
      accepted = true

      while i < text.size && accepted
        c = text[i]
        accepted = accept?(candidate, c)
        next unless accepted

        candidate += c
        i += 1

        if @legals.include?(candidate)
          best_candidate = candidate
          best_count = i
        end
      end
    end

    return if best_candidate.empty?

    @token = best_candidate
    @count = best_count
  end

  def tokens
    [@class.new(@token)]
  end

  private

  def accept?(candidate, c)
    token = candidate + c
    count = token.size - 1
    result = false

    @legals.each do |legal|
      result = true if legal[0..count] == token
    end

    result
  end
end

# Remark tokens (returns 2)
class RemarkTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)

    @legals = %w[REMARK REM]
    @count = 0
  end

  def count
    @count
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    best_candidate = ''
    best_count = 0

    if !text.empty? && text[0] != ' '
      candidate = ''
      i = 0
      accepted = true

      while i < text.size && accepted
        c = text[i]
        accepted = accept?(candidate, c)
        next unless accepted

        candidate += c
        i += 1

        if @legals.include?(candidate)
          best_candidate = candidate
          best_count = i
        end
      end
    end

    return if best_candidate.empty?

    @keyword_token = best_candidate
    remark = text[best_count..-1]
    @remark_token = remark[0] == ' ' ? remark[1..-1] : remark
    @count = text.size
  end

  def tokens
    tokens = []
    tokens << KeywordToken.new(@keyword_token)
    tokens << RemarkToken.new(@remark_token) unless @remark_token.empty?
    tokens
  end

  private

  def accept?(candidate, c)
    token = candidate + c
    count = token.size - 1
    result = false

    @legals.each do |legal|
      result = true if legal[0..count] == token
    end

    result
  end
end

# token reader for whitespace
class WhitespaceTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    /\A\s+/.match(text) { |m| @token = m[0] }
  end

  def tokens
    [WhitespaceToken.new(@token)]
  end
end

# token reader for comments
class CommentTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled

    comment_leads = []
    comment_leads << "'" if $options['apostrophe_comment'].value

    @token = text if !text.empty? && comment_leads.include?(text[0])
  end

  def tokens
    [CommentToken.new(@token)]
  end
end

# token reader for quoted text constants
class QuotedTextTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled

    quotes = ['"']

    /\A"[^"]*"/.match(text) { |m| @token = m[0] } if quotes.include?('"')

    /\A'[^']*'/.match(text) { |m| @token = m[0] } if quotes.include?("'")

    # allow for text literal without closing quote
    # add the proper closing quote
    if @token.empty?
      if quotes.include?('"')
        /\A"[^"]*/.match(text) { |m| @token = m[0] + '"' }
      end

      if quotes.include?("'")
        /\A'[^']*/.match(text) { |m| @token = m[0] + "'" }
      end
    end
  end

  def tokens
    [QuotedTextLiteralToken.new(@token)]
  end
end

# token reader for numeric constants in input channels (READ, INPUT)
class InputNumberTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    regexes = [
      /\A[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?/,
      /\A[+-]?\d+\.(\{[A-Za-z0-9\+\- _]*\})?/,
      /\A[+-]?\d+E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?/,
      /\A[+-]?\d+\.E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?/,
      /\A[+-]?\d+\.\d+(\{[A-Za-z0-9\+\- _]*\})?/,
      /\A[+-]?\d+\.\d+E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?/,
      /\A[+-]?\.\d+(\{[A-Za-z0-9\+\- _]*\})?/,
      /\A[+-]?\.\d+E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?/
    ]

    regexes.each { |regex| regex.match(text) { |m| @token = m[0] } }
  end

  def tokens
    [NumericLiteralToken.new(@token)]
  end
end

# token reader for numeric constants
class NumberTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def count
    @count
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    candidate = ''

    if !text.empty? && text[0] != ' '
      i = 0
      accepted = true

      while i < text.size && accepted
        c = text[i]
        accepted = accept?(candidate, c)

        if accepted
          candidate += c
          i += 1
        end
      end

      # if the candidate ends with 'E', remove it
      # the tokenbuilder takes as many as possible,
      # but a trailing 'E' is not valid
      if candidate[-1] == 'E'
        candidate = candidate[0..-2]
        i -= 1

        # back up to the 'E' in the input text
        i -= 1 while text[i] != 'E'
      end
    end

    # check that string conforms to one of these
    regexes = [
      /\A\d+(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A\d+\.(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A\d+E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A\d+\.E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A\d+\.\d+(E[+-]?\d+)?(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A\.\d+(E[+-]?\d+)?(\{[A-Za-z0-9\+\- _]*\})?\z/
    ]

    regexes.each { |regex| regex.match(candidate) { |m| @token = m[0] } }

    @count = i unless @token.empty?
  end

  def tokens
    [NumericLiteralToken.new(@token)]
  end

  private

  def accept?(candidate, c)
    result = false

    return false if candidate.size.positive? && candidate[-1] == '}'

    if candidate.include?('{')
      result = true if c =~ /[\w _\+\-\}]/
    else
      # can always append a digit
      result = true if c =~ /[0-9]/

      # can append a decimal point if no decimal point and no E
      result = true if c == '.' && candidate.count('.', 'E').zero?

      # can append E if no E and at least one digit (not just decimal point)
      result = true if c == 'E' &&
                       candidate.count('E').zero? &&
                       !candidate.count('0-9').zero?

      # can append sign if no chars or last char was E
      result = true if c == '+' && (candidate.empty? || candidate[-1] == 'E')
      result = true if c == '-' && (candidate.empty? || candidate[-1] == 'E')

      # can append a units sigil
      result = true if c == '{'
    end

    result
  end
end

# token reader for integer constants
class IntegerTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def count
    @count
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    candidate = ''

    if !text.empty? && text[0] != ' '
      i = 0
      accepted = true

      while i < text.size && accepted
        c = text[i]
        accepted = accept?(candidate, c)

        if accepted
          candidate += c
          i += 1
        end
      end
    end

    # check that string conforms to one of these
    regexes = [
      /\A\d+%(\{[A-Za-z0-9\+\- _]*\})?/
    ]

    regexes.each { |regex| regex.match(candidate) { |m| @token = m[0] } }

    @count = i unless @token.empty?
  end

  def tokens
    [IntegerLiteralToken.new(@token)]
  end

  private

  def accept?(candidate, c)
    result = false

    return false if candidate.size.positive? && candidate[-1] == '}'

    if candidate.include?('{')
      result = true if c =~ /[\w _\+\-\}]/
    else
      # can always append one percent char
      result = true if c == '%' && candidate.count('%').zero?

      # can append a digit if no percent char
      result = true if c =~ /[0-9]/ && candidate.count('%').zero?

      # can append a units sigil
      result = true if c == '{'
    end

    result
  end
end

# token reader for numeric symbols
class NumericSymbolTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def count
    @count
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    legals = %w[PI EUL AUR]

    candidate = ''
    i = 0

    legals.each do |symbol|
      if text.start_with?(symbol) && symbol.size > candidate.size
        candidate = symbol
        i = symbol.size
      end
    end

    @token = candidate if legals.include?(candidate)
    @count = i unless @token.empty?
  end

  def tokens
    [NumericSymbolToken.new(@token)]
  end
end

# token reader for variables
class VariableTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens, long_names)
    super(default_enabled, trigger_tokens)

    @long_names = long_names
  end

  def count
    @count
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    candidate = ''

    if !text.empty? && text[0] != ' '
      i = 0
      accepted = true

      while i < text.size && accepted
        c = text[i]
        accepted = accept?(candidate, c)

        if accepted
          candidate += c
          i += 1
        end
      end
    end

    # check that string conforms to one of these
    regexes = [
      /\A[A-Z]+\z/,
      /\A[A-Z]+\d+\z/,
      /\A[A-Z]+\$\z/,
      /\A[A-Z]+\d+\$\z/,
      /\A[A-Z]+%\z/,
      /\A[A-Z]+\d+%\z/
    ]

    regexes.each { |regex| regex.match(candidate) { |m| @token = m[0] } }

    @count = i unless @token.empty?
  end

  def tokens
    [VariableToken.new(@token)]
  end

  private

  def accept?(candidate, c)
    @long_names ? accept_long?(candidate, c) : accept_short?(candidate, c)
  end

  def accept_short?(candidate, c)
    result = false

    # can always start with an alpha
    result = true if c =~ /[A-Z]/ && candidate.empty?

    # can append a digit to a single character
    result = true if c =~ /[0-9]/ && (candidate =~ /\A[A-Z]\z/)

    # can append a dollar sign if one is not there
    result = true if
      c == '$' && !candidate.empty? && !['$', '%'].include?(candidate[-1])

    # can append a percent sign if one is not there
    result = true if
      c == '%' && !candidate.empty? && !['$', '%'].include?(candidate[-1])

    result
  end

  def accept_long?(candidate, c)
    result = false

    # can always start with an alpha
    if c =~ /[A-Z]/ && (candidate.empty? || candidate =~ /\A[A-Z]+\z/)
      result = true
    end

    # can append a digit to alphas and digits
    result = true if c =~ /[0-9]/ && (candidate =~ /\A[A-Z]+[0-9]*\z/)

    # can append a dollar sign if one is not there
    result = true if
      c == '$' && !candidate.empty? && !['$', '%'].include?(candidate[-1])

    # can append a percent sign if one is not there
    result = true if
      c == '%' && !candidate.empty? && !['$', '%'].include?(candidate[-1])

    result
  end
end

# token reader for unquoted text constants in DATA statements
class BareTextTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    token = ''

    # don't use \w because we don't want underscores
    /\A[A-Za-z0-9][A-Za-z0-9\s]+/.match(text) { |m| token = m[0] }

    # discard trailing spaces
    @token = token.rstrip

    # if it could be a numeric value, don't take it
    regexes = [
      /\A\d+\z/,
      /\A\d+E\d+\z/
    ]

    items = @token.split

    all_items_are_numbers = !items.empty?

    items.each do |item|
      item_is_number = false

      regexes.each do |regex|
        regex.match(item) { |_| item_is_number = true }
      end

      all_items_are_numbers &&= item_is_number
    end

    @token = '' if all_items_are_numbers
  end

  def tokens
    [BareTextLiteralToken.new(@token)]
  end
end

# token reader for unquoted text constants in INPUT statements
class InputTextTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    token = ''

    # accept anything up to separators, cannot start with space
    /\A[^ ,;][^,;]*/.match(text) { |m| token = m[0] }

    # discard trailing spaces
    @token = token.rstrip

    # if it could be a numeric value, or seriers of numeric values, don't take it
    regexes = [
      /\A[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A[+-]?\d+\.(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A[+-]?\d+E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A[+-]?\d+\.E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A[+-]?\d+\.\d+(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A[+-]?\d+\.\d+E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A[+-]?\.\d+(\{[A-Za-z0-9\+\- _]*\})?\z/,
      /\A[+-]?\.\d+E[+-]?\d+(\{[A-Za-z0-9\+\- _]*\})?\z/
    ]

    items = @token.split

    all_items_are_numbers = !items.empty?

    items.each do |item|
      item_is_number = false

      regexes.each do |regex|
        regex.match(item) { |_| item_is_number = true }
      end

      all_items_are_numbers &&= item_is_number
    end

    @token = '' if all_items_are_numbers
  end

  def tokens
    [BareTextLiteralToken.new(@token)]
  end
end

# token reader for PRINT USING numeric
class NumericFormatTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    candidate = ''
    i = 0
    accepted = true

    while i < text.size && accepted
      c = text[i]
      accepted = accept?(candidate, c)

      if accepted
        candidate += c
        i += 1
      end
    end

    @token = candidate
  end

  def tokens
    [NumericFormatToken.new(@token)]
  end

  private

  def accept?(candidate, c)
    result = false

    result = true if c == '#'
    result = true if c == '.' && !candidate.empty? && !candidate.include?('.')
    result = true if c == ',' && !candidate.empty? && !candidate.include?(',')
    result = true if c == '*' && (candidate.empty? || candidate[-1] == '*')

    result
  end
end

# token reader for PRINT USING character
class CharFormatTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    @token += text[0] if !text.empty? && text[0] == '!'
  end

  def tokens
    [CharFormatToken.new(@token)]
  end
end

# token reader for PRINT USING plain string
class PlainStringFormatTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    @token += text[0] if text.size.positive? && text[0] == '&'
  end

  def tokens
    [PlainStringFormatToken.new(@token)]
  end
end

# token reader for PRINT USING padded string
class PaddedStringFormatTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    /\A\\ *\\/.match(text) { |m| @token = m[0] }
  end

  def tokens
    [PaddedStringFormatToken.new(@token)]
  end
end

# token reader for PRINT USING constant
class ConstantFormatTokenBuilder < AbstractTokenBuilder
  def initialize(default_enabled, trigger_tokens)
    super(default_enabled, trigger_tokens)
  end

  def try(text)
    @token = ''
    @count = 0

    return unless @enabled
    
    while !text.empty? && !'#!&\\*'.include?(text[0])
      @token += text[0]
      text = text[1..-1]
    end
  end

  def tokens
    [ConstantFormatToken.new(@token)]
  end
end
