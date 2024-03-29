# frozen_string_literal: true

# class for type sigils
class Sigils
  def self.make_type_sigil(type)
    sigil_chars = {
      numeric: '.',
      integer: '%',
      string: '$',
      boolean: '?',
      filehandle: 'FH'
    }

    sigil_chars[type]
  end

  def self.make_shape_sigil(shape)
    sigil = ''
    sigil = '()' if shape == :array
    sigil = '(,)' if shape == :matrix
    sigil
  end

  def self.make_sigils_1(arguments)
    return nil if arguments.nil?

    sigils = []

    arguments.each do |arg|
      content_type = :empty
      # TODO: I think we can remove check for Array
      if arg.class.to_s == 'Array'
        # an array is a parsed expression
        unless arg.empty?
          a0 = arg[-1]
          content_type = a0.content_type
        end
      else
        content_type = arg.content_type
      end

      sigils << Sigils.make_type_sigil(content_type)
    end

    sigils
  end

  def self.format_sigils(sigils)
    return '' if sigils.nil?

    "(#{sigils.join(',')})"
  end

  def self.make_sigils_2(types, shapes)
    return nil if types.nil? || shapes.nil?

    msg = "Different number of types (#{types.count}) and shapes (#{shapes.count})"
    raise BASICExpressionError, msg unless
      types.count == shapes.count

    sigils = []

    types.each_with_index do |type, index|
      unless type == :empty
        sigils << Sigils.make_type_sigil(type) + Sigils.make_shape_sigil(shapes[index])
      end
    end

    sigils
  end
end

# class for all element classes
class AbstractElement
  def self.make_coord(c)
    [NumericValue.new(c)]
  end

  def self.make_coords(r, c)
    [NumericValue.new(r), NumericValue.new(c)]
  end

  attr_reader :precedence

  def initialize
    @empty = false
    @operator = false
    @function = false
    @user_function = false
    @variable = false
    @operand = false
    @terminal = false
    @group_start = false
    @group_end = false
    @param_start = false
    @separator = false
    @file_handle = false
    @precedence = 0
    @shape = nil
    @list = false
    @carriage = false
    @valref = nil
    @set_dims = false
    @numeric_constant = false
    @text_constant = false
    @boolean_constant = false
  end

  def uncache
    @cached = nil
  end

  def dump
    "#{self.class}:Unimplemented"
  end

  def destinations(_)
    []
  end

  def empty?
    @empty
  end

  def keyword?
    false
  end

  def operator?
    @operator
  end

  def function?
    @function
  end

  def user_function?
    @user_function
  end

  def variable?
    @variable
  end

  def function_variable?
    function? || variable?
  end

  def operand?
    @operand
  end

  def terminal?
    @terminal
  end

  def group_start?
    @group_start
  end

  def group_end?
    @group_end
  end

  def param_start?
    @param_start
  end

  def starter?
    @group_start || @param_start
  end

  def separator?
    @separator
  end

  def group_separator?
    group_start? || group_end? || separator?
  end

  def previous_is_array(stack)
    !stack.empty? && stack[-1].class.to_s == 'Array'
  end

  def file_handle?
    @file_handle
  end

  def scalar?
    @shape == :scalar
  end

  def array?
    @shape == :array
  end

  def matrix?
    @shape == :matrix
  end

  def list?
    @list
  end

  def carriage_control?
    @carriage
  end

  def value?
    @valref == :value
  end

  def reference?
    @valref == :reference
  end

  def numeric_constant?
    @numeric_constant
  end

  def text_constant?
    @text_constant
  end

  def boolean_constant?
    @boolean_constant
  end

  def pop_stack(stack); end

  private

  def make_signature(types, shapes)
    return '' if types.nil? || shapes.nil?

    sigils = Sigils.make_sigils_2(types, shapes)

    Sigils.format_sigils(sigils)
  end
end

# empty token
class EmptyToken < AbstractElement
  def initialize
    super

    @text = ''
    @empty = true
  end
end

# beginning of a group
class GroupStart < AbstractElement
  def self.accept?(token)
    classes = %w[GroupStartToken]
    classes.include?(token.class.to_s)
  end

  attr_reader :text

  def initialize(element)
    super()

    @text = element.to_s
    @group_start = true
  end

  def to_s
    @text
  end
end

# end of a group
class GroupEnd < AbstractElement
  def self.accept?(token)
    classes = %w[GroupEndToken]
    classes.include?(token.class.to_s)
  end

  def initialize(element)
    super()

    @text = element.to_s
    @group_end = true
    @operand = true
  end

  def match?(start_element)
    (start_element.text == '(' && @text == ')') ||
      (start_element.text == '[' && @text == ']')
  end

  def to_s
    @text
  end
end

# beginning of a set of parameters
class ParamStart < AbstractElement
  attr_reader :text

  def initialize(element)
    super()

    @text = element.to_s
    @param_start = true
  end

  def to_s
    @text
  end
end

# separator for group or params
class ParamSeparator < AbstractElement
  def self.accept?(token)
    classes = %w[ParamSeparatorToken]
    classes.include?(token.class.to_s)
  end

  def initialize(token)
    super()

    @text = token.to_s
    @separator = true
  end

  def to_s
    @text
  end
end

# class for units
class Units
  def self.new_empty
    Units.new({}, '')
  end

  def self.new_values(values)
    Units.new(values, nil)
  end

  def self.new_text(text)
    Units.new({}, text)
  end

  attr_reader :values

  def initialize(values, text)
    @values = values

    unless text.nil?
      name = ''
      power_s = ''
      last_c = ''

      text.each_char do |c|
        if is_alpha(c)
          if !name.empty? && (is_digit(last_c) || '+-'.include?(last_c))
            power_s = '1' if '+-'.include?(power_s)
            # TODO: check powers in range -3..3
            # TODO: check no duplicate name
            @values[name] = power_s.to_i
            name = ''
            power_s = ''
          end

          name += c

          last_c = c
        end

        if is_digit(c)
          power_s += c

          last_c = c
        end

        next unless '+-'.include?(c) && power_s.empty?

        power_s += c

        last_c = c
      end

      unless name.empty?
        power_s = '1' if '+-'.include?(power_s)
        # TODO: check powers in range -3..3
        # TODO: check no duplicate name
        @values[name] = power_s.to_i
      end
    end
  end

  def hash
    @values.hash
  end

  def eql?(other)
    @values == other.values
  end

  def <=>(other)
    # smaller set is always less
    return @values.size <=> other.values.size if
      @values.size != other.values.size

    # sizes are the same
    # smaller key always less
    a_key_sort = @values.keys.sort
    b_key_sort = other.values.keys.sort
    return a_key_sort <=> b_key_sort if
      a_key_sort != b_key_sort

    # keys are the same
    # smaller value always less
    a_key_sort.each do |key|
      return @values[key] <=> other.values[key] if
        @values[key] != other.values[key]
    end

    # units are the same
    0
  end

  def ==(other)
    @values == other.values
  end

  def empty?
    @values.empty?
  end

  def size
    @values.size
  end

  def even?
    even = true

    @values.each { |_name, power| even &&= power.even? }

    even
  end

  def key?(name)
    @values.key?(name)
  end

  def to_s
    units_t = ''

    unless @values.empty?
      units_s = []

      @values.each do |name, power|
        units_s << if power == 1
                     # don't print power when it is 1
                     name
                   else
                     # print all other powers
                     "#{name}#{power}"
                   end
      end

      units_t = "{#{units_s.join(' ')}}"
    end

    units_t
  end

  def add(other)
    raise BASICRuntimeError, :te_units_no_match unless @values == other.values

    clone
  end

  def subtract(other)
    raise BASICRuntimeError, :te_units_no_match unless @values == other.values

    clone
  end

  def multiply(other)
    new_values = @values.clone

    other.values.each do |name, power|
      new_power = if new_values.key?(name)
                    new_values[name] + power
                  else
                    power
                  end

      if new_power == 0
        new_values.delete(name)
      else
        new_values[name] = new_power
      end
    end

    Units.new_values(new_values)
  end

  def divide(other)
    new_values = @values.clone

    other.values.each do |name, power|
      new_power = if new_values.key?(name)
                    new_values[name] - power
                  else
                    -power
                  end

      if new_power == 0
        new_values.delete(name)
      else
        new_values[name] = new_power
      end
    end

    Units.new_values(new_values)
  end

  def power(other)
    # other is a NumericValue or IntegerValue, not a Units
    other_units = other.units

    raise BASICRuntimeError, :te_power_not_pure unless
      other_units.empty?

    # a value with units must use integer power
    # a pure value may have fractional power
    unless @values.empty?
      p = other.to_numeric.to_v
      p_i = p.to_i

      raise BASICRuntimeError, :te_power_not_int unless
        p_i == p
    end

    new_values = {}

    @values.each do |name, pow|
      new_values[name] = pow * p_i
    end

    Units.new_values(new_values)
  end

  def sqrt
    raise BASICRuntimeError, :te_power_not_even unless even?

    new_values = {}

    @values.each do |name, pow|
      new_values[name] = pow / 2
    end

    Units.new_values(new_values)
  end

  def exp
    raise BASICRuntimeError, :te_not_pure unless
      @values.empty?

    # result is always pure
    Units.new_empty
  end

  def log
    raise BASICRuntimeError, :te_not_pure unless
      @values.empty?

    # result is always pure
    Units.new_empty
  end

  def logb(_other)
    raise BASICRuntimeError, :te_not_pure unless
      @values.empty?

    # result is always pure
    Units.new_empty
  end

  def mod(other)
    raise BASICRuntimeError, :te_divisor_not_pure unless
      other.empty?

    # units after mod() are the same as original
    clone
  end

  private

  def is_digit(c)
    '0' <= c && c <= '9'
  end

  def is_alpha(c)
    ('A' <= c && c <= 'Z') || ('a' <= c && c <= 'z')
  end

  def is_alnum(c)
    ('A' <= c && c <= 'Z') || ('a' <= c && c <= 'z') || ('0' <= c && c <= '9')
  end
end

# class that holds a value
class AbstractValue < AbstractElement
  attr_reader :content_type, :shape, :warnings

  def initialize
    super

    @operand = true
    @precedence = 0
    @shape = :scalar
    @constant = false
    @value = nil
    @warnings = []
  end

  def hash
    @value.hash
  end

  def eql?(other)
    @value == other.to_v
  end

  def <=>(other)
    return -1 if self < other
    return 1 if self > other

    0
  end

  def ==(other)
    message = "Type mismatch (#{content_type}/#{other.content_type}) in =="

    raise(BASICExpressionError, message) unless compatible?(other)

    @value == other.to_v
  end

  def >(other)
    message = "Type mismatch (#{content_type}/#{other.content_type}) in >"

    raise(BASICExpressionError, message) unless compatible?(other)

    @value > other.to_v
  end

  def >=(other)
    message = "Type mismatch (#{content_type}/#{other.content_type}) in >="

    raise(BASICExpressionError, message) unless compatible?(other)

    @value >= other.to_v
  end

  def <(other)
    message = "Type mismatch (#{content_type}/#{other.content_type}) in <"

    raise(BASICExpressionError, message) unless compatible?(other)

    @value < other.to_v
  end

  def <=(other)
    message = "Type mismatch (#{content_type}/#{other.content_type}) in <="

    raise(BASICExpressionError, message) unless compatible?(other)

    @value <= other.to_v
  end

  def b_eq(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in b_eq()"

    raise(BASICExpressionError, message) unless compatible?(other)

    b = BooleanValue.new(@value == other.to_v)
    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'
    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'
    b
  end

  def b_ne(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in b_ne()"

    raise(BASICExpressionError, message) unless compatible?(other)

    b = BooleanValue.new(@value != other.to_v)
    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'
    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'
    b
  end

  def b_gt(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in b_gt()"

    raise(BASICExpressionError, message) unless compatible?(other)

    b = BooleanValue.new(@value > other.to_v)
    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'
    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'
    b
  end

  def b_ge(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in b_ge()"

    raise(BASICExpressionError, message) unless compatible?(other)

    b = BooleanValue.new(@value >= other.to_v)
    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'
    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'
    b
  end

  def b_lt(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in b_lt()"

    raise(BASICExpressionError, message) unless compatible?(other)

    b = BooleanValue.new(@value < other.to_v)
    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'
    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'
    b
  end

  def b_le(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in b_le()"

    raise(BASICExpressionError, message) unless compatible?(other)

    b = BooleanValue.new(@value <= other.to_v)
    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'
    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'
    b
  end

  def b_and(_)
    raise(BASICExpressionError, 'Invalid operator AND')
  end

  def b_or(_)
    raise(BASICExpressionError, 'Invalid operator OR')
  end

  def posate
    raise(BASICExpressionError, 'Invalid operator +')
  end

  def negate
    raise(BASICExpressionError, 'Invalid operator -')
  end

  def filehandle
    raise(BASICExpressionError, 'Invalid operator #')
  end

  def not
    raise(BASICExpressionError, 'Invalid operator NOT')
  end

  def add(_)
    raise(BASICExpressionError, 'Invalid operator add')
  end

  def subtract(_)
    raise(BASICExpressionError, 'Invalid operator subtract')
  end

  def multiply(_)
    raise(BASICExpressionError, 'Invalid operator multiply')
  end

  def divide(_)
    raise(BASICExpressionError, 'Invalid operator divide')
  end

  def power(_)
    raise(BASICExpressionError, 'Invalid operator power')
  end

  def dump
    "#{self.class}:#{self}"
  end

  def constant?
    @constant
  end

  def keyword?
    false
  end

  def evaluate(_, _)
    self
  end

  def to_v
    @value
  end

  def to_numeric
    @value
  end

  def compatible?(other)
    other.content_type == content_type
  end
end

# Numeric constants
class NumericValue < AbstractValue
  def self.new_2(token, units)
    n = NumericValue.new(token)
    n.set_units(units)

    n
  end

  def self.accept?(token)
    classes =
      %w[Fixnum Integer Bignum Float NumericLiteralToken NumericSymbolToken]

    classes.include?(token.class.to_s)
  end

  def self.numeric(text)
    case text
    # nnn(E+nn)
    when /\A\s*[+-]?\d+(E+?\d+)?\z/
      text.to_f.to_i
    # nnn(E-nn)
    when /\A\s*[+-]?\d+(E-\d+)?\z/
      text.to_f
    # nnn.(nnn)(E+-nn)
    when /\A\s*[+-]?\d+\.(\d*)?(E[+-]?\d+)?\z/
      text.to_f
    # (nnn).nnn(E+-nn)
    when /\A\s*[+-]?(\d+)?\.\d*(E[+-]?\d+)?\z/
      text.to_f
    end
  end

  def self.new_rand(interpreter, upper_bound)
    v = interpreter.rand(upper_bound)
    NumericValue.new(v)
  end

  private

  def float_to_possible_int(f)
    return f if f == Float::INFINITY

    i = f.to_i
    frac = f - i
    frac.zero? || (!i.zero? && frac.abs < 1e-7) ? i : f
  end

  public

  attr_reader :value, :symbol_text, :units

  def initialize(obj)
    super()

    numeric_classes = %w[Fixnum Integer Bignum Float]
    float_classes = %w[Rational NumericLiteralToken]

    f = nil
    f = obj.to_f if float_classes.include?(obj.class.to_s)
    f = obj if numeric_classes.include?(obj.class.to_s)

    if obj.class.to_s == 'NumericSymbolToken'
      f = obj.value
      @symbol = true
    end

    raise(BASICSyntaxError, "'#{obj}' is not a number") if f.nil?

    precision = $options['precision'].value
    if precision != 'INFINITE' && f != 0 && f != Float::INFINITY
      abs_value = f.abs
      log_value = Math.log10(abs_value)
      ceil_value = log_value.ceil
      num_digits = -(ceil_value - precision)
      f = f.round(num_digits)
    end

    @value = float_to_possible_int(f)

    @symbol_text = obj.to_s
    @content_type = :numeric
    @shape = :scalar
    @constant = true

    @numeric_constant = true
    @units = Units.new_empty
    @units = obj.units if obj.class.to_s == 'NumericLiteralToken'
  end

  def set_content_type(type_stack)
    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    constant_stack.push(@constant)
  end

  def set_units(units)
    @units = units
  end

  def hash
    @value.hash + @symbol_text.hash
  end

  def eql?(other)
    @value == other.to_v
  end

  def <=>(other)
    return @value <=> other.value if @value != other.value

    @units <=> other.units
  end

  def ==(other)
    @value == other.to_v
  end

  def >(other)
    @value > other.to_v
  end

  def >=(other)
    @value >= other.to_v
  end

  def <(other)
    @value < other.to_v
  end

  def <=(other)
    @value <= other.to_v
  end

  def b_and(other)
    b = BooleanValue.new(to_b && other.to_b)

    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'

    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'

    b
  end

  def b_or(other)
    b = BooleanValue.new(to_b || other.to_b)

    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'

    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'

    b
  end

  def posate
    NumericValue.new_2(@value, @units)
  end

  def negate
    NumericValue.new_2(-@value, @units)
  end

  def filehandle
    num = to_i
    FileHandle.new(num)
  end

  def not
    b = to_b
    BooleanValue.new(!b)
  end

  def add(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in add()"

    raise(BASICExpressionError, message) unless compatible?(other)

    value = @value + other.to_numeric.to_v
    units = @units.add(other.units)

    NumericValue.new_2(value, units)
  end

  def subtract(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in subtract()"

    raise(BASICExpressionError, message) unless compatible?(other)

    value = @value - other.to_numeric.to_v
    units = @units.subtract(other.units)

    NumericValue.new_2(value, units)
  end

  def multiply(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in multiply()"

    raise(BASICExpressionError, message) unless compatible?(other)

    value = @value * other.to_numeric.to_v
    units = @units.multiply(other.units)

    NumericValue.new_2(value, units)
  end

  def divide(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in divide()"

    raise(BASICExpressionError, message) unless compatible?(other)
    raise BASICRuntimeError, :te_div_zero if other.zero?

    value = @value.to_f / other.to_numeric.to_f
    units = @units.divide(other.units)

    NumericValue.new_2(value, units)
  end

  def power(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in power()"

    raise(BASICExpressionError, message) unless compatible?(other)

    value = @value**other.to_numeric.to_v
    units = @units.power(other)

    NumericValue.new_2(value, units)
  end

  def truncate
    value = @value.to_i

    NumericValue.new_2(value, @units)
  end

  def floor
    value = @value.floor

    NumericValue.new_2(value, @units)
  end

  def to_int
    IntegerValue.new_2(to_i, @units)
  end

  def exp
    value = Math.exp(@value)
    units = @units.exp

    NumericValue.new_2(value, units)
  end

  def log
    value = @value.positive? ? Math.log(@value) : 0
    units = @units.log

    NumericValue.new_2(value, units)
  end

  def logb(lbase)
    lbase_v = lbase.to_v
    value = @value.positive? ? Math.log(@value, lbase_v) : 0
    units = @units.log

    NumericValue.new_2(value, units)
  end

  def log10
    value = @value.positive? ? Math.log10(@value) : 0
    units = @units.log

    NumericValue.new_2(value, units)
  end

  def log2
    value = @value.positive? ? Math.log2(@value) : 0
    units = @units.log

    NumericValue.new_2(value, units)
  end

  def mod(other)
    value = other.to_numeric.to_v.zero? ? 0 : @value % other.to_numeric.to_v
    units = @units.mod(other.units)

    NumericValue.new_2(value, units)
  end

  def abs
    value = @value >= 0 ? @value.clone : -@value

    NumericValue.new_2(value, @units)
  end

  def no_units
    value = @value.clone
    units = Units.new_empty

    NumericValue.new_2(value, units)
  end

  def round(places)
    value = @value.round(places.to_i)

    NumericValue.new_2(value, @units)
  end

  def sqrt
    value = @value.positive? ? Math.sqrt(@value) : 0
    units = @units.sqrt

    NumericValue.new_2(value, units)
  end

  def to_rad(d)
    d * 3.14156926 / 180
  end

  def to_radians
    rad_name = $options['radians'].value

    new_units = Units.new_empty
    new_units = Units.new_values({ rad_name => 1 }) if
      $options['trig_require_units'].value

    new_value = to_rad(@value)
    NumericValue.new_2(new_value, new_units)
  end

  def to_deg(r)
    r * 180 / 3.14156926
  end

  def to_degrees
    deg_name = $options['degrees'].value

    new_units = Units.new_empty
    new_units = Units.new_values({ deg_name => 1 }) if
      $options['trig_require_units'].value

    new_value = to_deg(@value)
    NumericValue.new_2(new_value, new_units)
  end

  def sin
    if $options['trig_require_units'].value
      raise BASICRuntimeError.new(:te_require_units, @name) if
        @units.empty?
    end
 
    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    unless @units.empty?
      raise BASICRuntimeError.new(:te_wrong_units, @name) unless
        @units.size == 1 && (@units.key?(rad_name) || @units.key?(deg_name))
    end

    angle_in_radians = @value
    angle_in_radians = to_rad(@value) if @units.key?(deg_name)

    new_value = Math.sin(angle_in_radians)

    NumericValue.new(new_value)
  end

  def arcsin
    raise BASICRuntimeError.new(:te_not_pure, @name) unless @units.empty?

    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    new_units = Units.new_empty
    new_units = Units.new_values({ rad_name => 1 }) if
      $options['trig_require_units'].value

    new_value = 0
    new_value = Math.asin(@value) if @value >= -1.0 && @value <= 1.0

    NumericValue.new_2(new_value, new_units)
  end

  def cos
    if $options['trig_require_units'].value
      raise BASICRuntimeError.new(:te_require_units, @name) if
        @units.empty?
    end
 
    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    unless @units.empty?
      raise BASICRuntimeError.new(:te_wrong_units, @name) unless
        @units.size == 1 && (@units.key?(rad_name) || @units.key?(deg_name))
    end

    angle_in_radians = @value
    angle_in_radians = to_rad(@value) if @units.key?(deg_name)

    new_value = Math.cos(angle_in_radians)

    NumericValue.new(new_value)
  end

  def arccos
    raise BASICRuntimeError.new(:te_not_pure, @name) unless @units.empty?

    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    new_units = Units.new_empty
    new_units = Units.new_values({ rad_name => 1 }) if
      $options['trig_require_units'].value

    new_value = 0
    new_value = Math.acos(@value) if @value >= -1.0 && @value <= 1.0

    NumericValue.new_2(new_value, new_units)
  end

  def tan
    if $options['trig_require_units'].value
      raise BASICRuntimeError.new(:te_require_units, @name) if
        @units.empty?
    end
 
    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    unless @units.empty?
      raise BASICRuntimeError.new(:te_wrong_units, @name) unless
        @units.size == 1 && (@units.key?(rad_name) || @units.key?(deg_name))
    end

    angle_in_radians = @value
    angle_in_radians = to_rad(@value) if @units.key?(deg_name)

    new_value = angle_in_radians >= 0 ? Math.tan(angle_in_radians) : 0

    NumericValue.new(new_value)
  end

  def atn
    raise BASICRuntimeError.new(:te_not_pure, @name) unless @units.empty?

    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    new_units = Units.new_empty
    new_units = Units.new_values({ rad_name => 1 }) if
      $options['trig_require_units'].value

    new_value = Math.atan(@value)

    NumericValue.new_2(new_value, new_units)
  end

  def atn2(a2)
    raise BASICRuntimeError.new(:te_not_pure, @name) unless @units.empty?

    raise BASICRuntimeError.new(:te_not_pure, @name) unless a2.units.empty?

    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    new_units = Units.new_empty
    new_units = Units.new_values({ rad_name => 1 }) if
      $options['trig_require_units'].value

    new_value = Math.atan2(@value, a2.to_f)

    NumericValue.new_2(new_value, new_units)
  end

  def cot
    if $options['trig_require_units'].value
      raise BASICRuntimeError.new(:te_require_units, @name) if
        @units.empty?
    end
 
    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    unless @units.empty?
      raise BASICRuntimeError.new(:te_wrong_units, @name) unless
        @units.size == 1 && (@units.key?(rad_name) || @units.key?(deg_name))
    end

    angle_in_radians = @value
    angle_in_radians = to_rad(@value) if @units.key?(deg_name)

    cos = Math.cos(angle_in_radians)
    sin = Math.sin(angle_in_radians)
    cot = Float::INFINITY
    cot = cos / sin if sin.nonzero?

    NumericValue.new(cot)
  end

  def sec
    if $options['trig_require_units'].value
      raise BASICRuntimeError.new(:te_require_units, @name) if
        @units.empty?
    end
 
    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    unless @units.empty?
      raise BASICRuntimeError.new(:te_wrong_units, @name) unless
        @units.size == 1 && (@units.key?(rad_name) || @units.key?(deg_name))
    end

    angle_in_radians = @value
    angle_in_radians = to_rad(@value) if @units.key?(deg_name)

    cos = Math.cos(angle_in_radians)
    sec = Float::INFINITY
    sec = 1 / cos if cos.nonzero?
    NumericValue.new(sec)
  end

  def csc
    if $options['trig_require_units'].value
      raise BASICRuntimeError.new(:te_require_units, @name) if
        @units.empty?
    end
 
    deg_name = $options['degrees'].value
    rad_name = $options['radians'].value

    unless @units.empty?
      raise BASICRuntimeError.new(:te_wrong_units, @name) unless
        @units.size == 1 && (@units.key?(rad_name) || @units.key?(deg_name))
    end

    angle_in_radians = @value
    angle_in_radians = to_rad(@value) if @units.key?(deg_name)

    sin = Math.sin(angle_in_radians)
    csc = Float::INFINITY
    csc = 1 / sin if sin.nonzero?
    NumericValue.new(csc)
  end

  def sign
    result = 0
    result = 1 if @value.positive?
    result = -1 if @value.negative?

    NumericValue.new(result)
  end

  def dump
    "#{self.class}:#{@symbol_text}"
  end

  def zero?
    @value.zero?
  end

  def to_i
    @value.to_i
  end

  def to_f
    @value.to_f
  end

  def to_s
    @value.to_s + @units.to_s
  end

  def to_b
    !@value.to_f.zero?
  end

  def to_numeric
    NumericValue.new(@value)
  end

  def print(printer)
    s = to_formatted_s
    printer.print_item s
    printer.last_was_numeric
  end

  def write(printer)
    s = to_formatted_s
    printer.print_item s
  end

  def compatible?(other)
    other.numeric_constant? || other.boolean_constant?
  end

  private

  def to_formatted_s
    lead_space = @value >= 0 ? ' ' : ''

    lead_space + @value.to_s.upcase + @units.to_s
  end
end

# Integer constants
class IntegerValue < AbstractValue
  def self.new_2(token, units)
    n = IntegerValue.new(token)
    n.set_units(units)

    n
  end

  def self.accept?(token)
    classes = %w[Fixnum Integer Bignum Float IntegerLiteralToken]
    classes.include?(token.class.to_s)
  end

  def self.numeric(text)
    # nnn%
    text.to_f.to_i if /\A\s*[+-]?\d+%\z/ =~ text
  end

  def self.new_rand(interpreter, upper_bound)
    v = interpreter.rand(upper_bound)
    IntegerValue.new(v.to_i)
  end

  attr_reader :value, :symbol_text, :units

  def initialize(obj)
    super()

    numeric_classes = %w[Fixnum Integer Bignum Float IntegerLiteralToken]

    f = nil
    f = obj.to_i if numeric_classes.include?(obj.class.to_s)
    f = obj.to_f.to_i if obj.class.to_s == 'NumericLiteralToken'

    raise BASICSyntaxError, "'#{obj}' is not an integer" if f.nil?

    @value = f

    @symbol_text = obj.to_s
    @content_type = :integer
    @shape = :scalar
    @constant = true

    @numeric_constant = true
    @units = Units.new_empty
    @units = obj.units if obj.class.to_s == 'IntegerLiteralToken'
  end

  def set_content_type(type_stack)
    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    constant_stack.push(@constant)
  end

  def set_units(units)
    @units = units
  end

  def hash
    @value.hash + @symbol_text.hash
  end

  def eql?(other)
    @value == other.to_v
  end

  def <=>(other)
    return @value <=> other.value if @value != other.value

    @units <=> other.units
  end

  def ==(other)
    @value == other.to_v
  end

  def >(other)
    @value > other.to_v
  end

  def >=(other)
    @value >= other.to_v
  end

  def <(other)
    @value < other.to_v
  end

  def <=(other)
    @value <= other.to_v
  end

  def b_and(other)
    if other.content_type == :integer && $options['int_bitwise'].value
      IntegerValue.new(to_i & other.to_i)
    else
      b = BooleanValue.new(to_b && other.to_b)

      b = IntegerValue.new(b.to_ms_i) if
        $options['relational_result'].value == 'INTEGER'

      b = NumericValue.new(b.to_ms_i) if
        $options['relational_result'].value == 'NUMERIC'

      b
    end
  end

  def b_or(other)
    if other.content_type == :integer && $options['int_bitwise'].value
      IntegerValue.new(to_i | other.to_i)
    else
      b = BooleanValue.new(to_b || other.to_b)
      b = IntegerValue.new(b.to_ms_i) if
        $options['relational_result'].value == 'INTEGER'
      b = NumericValue.new(b.to_ms_i) if
        $options['relational_result'].value == 'NUMERIC'
      b
    end
  end

  def posate
    NumericValue.new_2(@value, @units)
  end

  def negate
    IntegerValue.new_2(-@value, @units)
  end

  def filehandle
    num = to_i
    FileHandle.new(num)
  end

  def not
    b = ~to_i
    IntegerValue.new(b)
  end

  def add(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in add()"

    raise(BASICExpressionError, message) unless compatible?(other)

    value = @value + other.to_numeric.to_v
    units = @units.add(other.units)

    IntegerValue.new_2(value, units)
  end

  def subtract(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in subtract()"

    raise(BASICExpressionError, message) unless compatible?(other)

    value = @value - other.to_numeric.to_v
    units = @units.subtract(other.units)

    IntegerValue.new_2(value, units)
  end

  def multiply(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in multiply()"

    raise(BASICExpressionError, message) unless compatible?(other)

    value = @value * other.to_numeric.to_v
    units = @units.multiply(other.units)

    IntegerValue.new_2(value, units)
  end

  def divide(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in divide()"

    raise(BASICExpressionError, message) unless compatible?(other)
    raise BASICRuntimeError, :te_div_zero if other.zero?

    value = @value.to_f / other.to_numeric.to_f
    units = @units.divide(other.units)

    IntegerValue.new_2(value, units)
  end

  def power(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in power()"

    raise(BASICExpressionError, message) unless compatible?(other)

    value = @value**other.to_numeric.to_v
    units = @units.power(other)

    IntegerValue.new_2(value, units)
  end

  def truncate
    value = @value.to_i

    IntegerValue.new_2(value, @units)
  end

  def floor
    IntegerValue.new_2(@value, @units)
  end

  def exp
    value = Math.exp(@value)
    units = @units.exp

    IntegerValue.new_2(value, units)
  end

  def log
    value = @value.positive? ? Math.log(@value) : 0
    units = @units.log

    IntegerValue.new_2(value, units)
  end

  def log10
    value = @value.positive? ? Math.log10(@value) : 0
    units = @units.log

    IntegerValue.new_2(value, units)
  end

  def log2
    value = @value.positive? ? Math.log2(@value) : 0
    units = @units.log

    IntegerValue.new_2(value, units)
  end

  def mod(other)
    value = other.to_numeric.zero? ? 0 : @value % other.to_numeric.to_v
    units = @units.mod(other.units)

    IntegerValue.new_2(value, units)
  end

  def abs
    value = @value >= 0 ? @value : -@value

    IntegerValue.new_2(value, @units)
  end

  def sqrt
    value = @value.positive? ? Math.sqrt(@value) : 0
    units = @units.sqrt

    IntegerValue.new_2(value, units)
  end

  def sin
    value = Math.sin(@value)
    IntegerValue.new(value)
  end

  def cos
    value = Math.cos(@value)
    IntegerValue.new(value)
  end

  def tan
    value = @value >= 0 ? Math.tan(@value) : 0
    IntegerValue.new(value)
  end

  def atn
    value = Math.atan(@value)
    IntegerValue.new(value)
  end

  def sign
    result = 0
    result = 1 if @value.positive?
    result = -1 if @value.negative?

    IntegerValue.new(result)
  end

  def zero?
    @value.zero?
  end

  def to_i
    @value.to_i
  end

  def to_f
    @value.to_i
  end

  def to_s
    @value.to_s + @units.to_s
  end

  def to_b
    !@value.to_i.zero?
  end

  def to_numeric
    IntegerValue.new(@value)
  end

  def print(printer)
    s = to_formatted_s
    printer.print_item s
    printer.last_was_numeric
  end

  def write(printer)
    s = to_formatted_s
    printer.print_item s
  end

  def compatible?(other)
    other.numeric_constant? || other.boolean_constant?
  end

  private

  def to_formatted_s
    lead_space = @value >= 0 ? ' ' : ''

    lead_space + @value.to_s.upcase + @units.to_s
  end
end

# Text constants
class TextValue < AbstractValue
  def self.accept?(token)
    classes = %w[QuotedTextLiteralToken BareTextLiteralToken TextSymbolToken String]
    classes.include?(token.class.to_s)
  end

  def self.new_rand(interpreter, length, set)
    # negative length means random length up to positive value
    if length.negative?
      v1 = interpreter.rand(NumericValue.new(-length))
      v2 = v1 + 1
      length = v2.to_i
    end

    # generate N characters from specified set
    s = ''

    (1..length).each do
      v1 = interpreter.rand(NumericValue.new(set.size))
      v2 = v1.to_i
      raise StandardError, 'RND$ out of range' if v2 >= set.size

      c = set[v2]
      s += c
    end

    TextValue.new(s)
  end

  attr_reader :value, :symbol_text

  def initialize(text)
    super()

    @value = nil
    @value = text if text.class.to_s == 'String'
    @value = text.value if text.class.to_s == 'QuotedTextLiteralToken'
    @value = text.value if text.class.to_s == 'BareTextLiteralToken'

    raise BASICSyntaxError, "'#{text}' is not a text constant" if @value.nil?

    @content_type = :string
    @shape = :scalar
    @constant = true

    @text_constant = true
  end

  def set_content_type(type_stack)
    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    constant_stack.push(@constant)
  end

  def hash
    @value.hash
  end

  def eql?(other)
    @value == other.to_v
  end

  def <=>(other)
    @value <=> other.to_v
  end

  def ==(other)
    @value == other.to_v
  end

  def >(other)
    @value > other.to_v
  end

  def >=(other)
    @value >= other.to_v
  end

  def <(other)
    @value < other.to_v
  end

  def <=(other)
    @value <= other.to_v
  end

  def b_and(other)
    b = BooleanValue.new(to_b && other.to_b)

    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'

    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'

    b
  end

  def b_or(other)
    b = BooleanValue.new(to_b || other.to_b)

    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'

    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'

    b
  end

  def not
    b = to_b
    BooleanValue.new(!b)
  end

  def add(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in add()"

    raise(BASICExpressionError, message) unless compatible?(other)

    TextValue.new(@value + other.to_v)
  end

  def multiply(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in multiply()"

    raise(BASICExpressionError, message) unless other.numeric_constant?

    TextValue.new(@value * other.to_v)
  end

  def to_s
    "\"#{@value}\""
  end

  def to_b
    !@value.size.zero?
  end

  def print(printer)
    printer.print_item @value
  end

  def write(printer)
    v = to_s
    printer.print_item v
  end

  def na_unpack
    base = $options['base'].value

    length = NumericValue.new(@value.size + base)
    dims = [length]

    values = {}

    index = base

    @value.each_char do |char|
      key = [NumericValue.new(index)]
      values[key] = NumericValue.new(char.ord)
      index += 1
    end

    BASICArray.new(dims, values)
  end

  def ia_unpack
    base = $options['base'].value

    length = IntegerValue.new(@value.size + base)
    dims = [length]

    values = {}

    index = base

    @value.each_char do |char|
      key = [NumericValue.new(index)]
      values[key] = IntegerValue.new(char.ord)
      index += 1
    end

    BASICArray.new(dims, values)
  end

  def lower
    TextValue.new(@value.downcase)
  end

  def upper
    TextValue.new(@value.upcase)
  end
end

# Boolean constants
class BooleanValue < AbstractValue
  def self.accept?(token)
    classes = %w[BooleanLiteralToken]
    classes.include?(token.class.to_s)
  end

  attr_reader :value, :symbol_text

  def initialize(obj)
    super()

    obj_class = obj.class.to_s
    @symbol_text = obj.to_s

    @value =
      (obj_class == 'BooleanLiteralToken' && obj.to_s == 'TRUE') ||
      (obj_class == 'String' && obj.casecmp('TRUE').zero?) ||
      (obj_class == 'NumericValue' && !obj.to_f.zero?) ||
      (obj_class == 'IntegerValue' && !obj.to_i.zero?) ||
      (obj_class == 'TextValue' && !obj.value.strip.size.zero?) ||
      obj_class == 'TrueClass'

    @content_type = :boolean
    @shape = :scalar
    @constant = true
    @boolean_constant = true
  end

  def set_content_type(type_stack)
    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    constant_stack.push(@constant)
  end

  def hash
    @value.hash
  end

  def eql?(other)
    to_i == other.to_i
  end

  def <=>(other)
    to_i <=> other.to_i
  end

  def ==(other)
    to_i == other.to_i
  end

  def >(other)
    to_i > other.to_i
  end

  def >=(other)
    to_i >= other.to_i
  end

  def <(other)
    to_i < other.to_i
  end

  def <=(other)
    to_i <= other.to_i
  end

  def not
    BooleanValue.new(!@value)
  end

  def b_and(other)
    b = BooleanValue.new(@value && other.to_b)

    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'

    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'

    b
  end

  def b_or(other)
    b = BooleanValue.new(@value || other.to_b)

    b = IntegerValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'INTEGER'

    b = NumericValue.new(b.to_ms_i) if
      $options['relational_result'].value == 'NUMERIC'

    b
  end

  def add(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in add()"

    raise(BASICExpressionError, message) unless other.numeric_constant?

    value = numeric_value + other.to_v
    NumericValue.new(value)
  end

  def subtract(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in subtract()"

    raise(BASICExpressionError, message) unless other.numeric_constant?

    value = numeric_value - other.to_v
    NumericValue.new(value)
  end

  def multiply(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in multiply()"

    raise(BASICExpressionError, message) unless other.numeric_constant?

    value = numeric_value * other.to_v
    NumericValue.new(value)
  end

  def divide(other)
    message =
      "Type mismatch (#{content_type}/#{other.content_type}) in divide()"

    raise(BASICExpressionError, message) unless other.numeric_constant?
    raise BASICRuntimeError, :te_div_zero if other.zero?

    value = numeric_value.to_f / other.to_f
    NumericValue.new(value)
  end

  def to_i
    @value ? 1 : 0
  end

  def to_f
    @value ? 1.0 : 0.0
  end

  def to_ms_i
    @value ? -1 : 0
  end

  def to_s
    @value ? 'true' : 'false'
  end

  def to_formatted_s
    @value ? 'true' : 'false'
  end

  def to_b
    @value
  end

  def to_numeric
    @value ? NumericValue.new(-1) : NumericValue.new(0)
  end

  def print(printer)
    s = to_formatted_s
    printer.print_item s
    printer.last_was_numeric
  end

  def write(printer)
    s = to_formatted_s
    printer.print_item s
  end

  def compatible?(other)
    other.numeric_constant? || other.boolean_constant?
  end

  private

  def numeric_value
    @value ? -1 : 0
  end
end

# File handle class
class FileHandle < AbstractElement
  attr_reader :number

  def initialize(num)
    super()

    legals = %w[Fixnum Integer NumericValue IntegerValue FileHandle]

    raise BASICRuntimeError, :te_fh_inv unless
      legals.include?(num.class.to_s)

    raise BASICRuntimeError, :te_fnum_inv if num.to_i.negative?

    @number = num.to_i
    @file_handle = true
  end

  def hash
    @number.hash
  end

  def eql?(other)
    @number == other.number
  end

  def warnings
    []
  end

  def to_s
    "##{@number}"
  end

  def to_i
    @number
  end
end

# Carriage control for PRINT and MAT PRINT statements
class CarriageControl
  def self.accept?(token)
    classes = %w[ParamSeparatorToken]
    classes.include?(token.class.to_s)
  end

  attr_reader :comprehension_effort

  def initialize(token)
    token = ',' if token == 'COMMA'
    token = ';' if token == 'SEMI'
    token = '' if token == 'NONE'

    @operator = token.to_s
    @carriage = true
    @file_handle = false
    @comprehension_effort = 0
  end

  def warnings
    []
  end

  def uncache; end

  def keyword?
    false
  end

  def has_tab
    false
  end

  def to_s
    case @operator
    when ';'
      '; '
    when ','
      ', '
    when 'NL'
      ''
    when ''
      ' '
    end
  end

  def dump
    ["#{self.class}:#{@operator}"]
  end

  def carriage_control?
    @carriage
  end

  def filehandle?
    @file_handle
  end

  def numerics
    []
  end

  def strings
    []
  end

  def booleans
    []
  end

  def variables
    []
  end

  def operators
    []
  end

  def functions
    []
  end

  def userfuncs
    []
  end

  def plot(printer)
    printer.newline
  end

  def print(printer)
    case @operator
    when ','
      printer.tab
    when ';'
      printer.semicolon
    when 'NL'
      printer.newline
    when ''
      printer.implied
    end
  end

  def write(printer)
    case @operator
    when ',', ';'
      printer.print_item(@operator)
    when 'NL'
      printer.newline
    when ''
      printer.print_item(',')
    end
  end
end

# Hold a variable name
class VariableName < AbstractElement
  def self.accept?(token)
    classes = %w[VariableToken]
    classes.include?(token.class.to_s)
  end

  attr_reader :name, :content_type

  def initialize(token)
    super()

    raise(BASICSyntaxError, "'#{token}' is not a variable token") unless
      token.class.to_s == 'VariableToken'

    @name = token.text
    @variable = true
    @operand = true
    @precedence = 10
    @content_type = token.content_type
  end

  def hash
    @name.hash
  end

  def eql?(other)
    to_s == other.to_s
  end

  def <=>(other)
    to_s <=> other.to_s
  end

  def ==(other)
    to_s == other.to_s
  end

  def <(other)
    to_s < other.to_s
  end

  def <=(other)
    to_s <= other.to_s
  end

  def >(other)
    to_s > other.to_s
  end

  def >=(other)
    to_s >= other.to_s
  end

  def scalar?
    true
  end

  def dump
    result = Sigils.make_type_sigil(@content_type)
    "#{self.class}:#{@name} -> #{result}"
  end

  def compatible?(value)
    numerics = %i[numeric integer]
    strings = %i[string]

    case content_type
    when :numeric, :integer
      numerics.include?(value.content_type)
    when :string
      strings.include?(value.content_type)
    else
      false
    end
  end

  def subscripts
    []
  end

  def to_s
    @name.to_s
  end
end

# Hold a function name
class AbstractFunctionName < AbstractElement
  attr_reader :name, :content_type

  def initialize(token)
    super()

    @name = token.text
    @function = true
    @operand = true
    @precedence = 10
    @content_type = token.content_type
  end

  def hash
    @name.hash
  end

  def eql?(other)
    to_s == other.to_s
  end

  def <=>(other)
    to_s <=> other.to_s
  end

  def ==(other)
    to_s == other.to_s
  end

  def <(other)
    to_s < other.to_s
  end

  def <=(other)
    to_s <= other.to_s
  end

  def >(other)
    to_s > other.to_s
  end

  def >=(other)
    to_s >= other.to_s
  end

  def scalar?
    true
  end

  def default_shape
    :scalar
  end

  def dump
    result = Sigils.make_type_sigil(@content_type)
    "#{self.class}:#{@name} -> #{result}"
  end

  def compatible?(value)
    numerics = %i[numeric integer]
    strings = %i[string]

    case content_type
    when :numeric, :integer
      numerics.include?(value.content_type)
    when :string
      strings.include?(value.content_type)
    else
      false
    end
  end

  def subscripts
    []
  end

  def to_s
    @name.to_s
  end

  def to_sw
    @name.to_s
  end
end

class FunctionName < AbstractFunctionName
  def self.accept?(token)
    classes = %w[FunctionToken]
    classes.include?(token.class.to_s)
  end

  def initialize(token)
    super

    raise(BASICSyntaxError, "'#{token}' is not a function name") unless
      token.class.to_s == 'FunctionToken'

    @user_function = false
  end
end

class UserFunctionName < AbstractFunctionName
  def self.accept?(token)
    classes = %w[UserFunctionToken]
    classes.include?(token.class.to_s)
  end

  def initialize(token)
    super

    raise(BASICSyntaxError, "'#{token}' is not a function name") unless
      token.class.to_s == 'UserFunctionToken'

    @user_function = true
  end
end

# empty variable, used only for NEXT without control variable
class EmptyVariable
  def name
    EmptyToken.new
  end

  def empty?
    true
  end
end

# Hold a variable (name with possible subscripts and value)
class Variable < AbstractElement
  attr_writer :valref, :set_dims
  attr_reader :content_type, :shape, :subscripts, :warnings

  def initialize(variable_name, my_shape, subscripts, wrapped_subscripts)
    super()

    raise(BASICSyntaxError, "'#{variable_name}' is not a variable name") unless
      variable_name.class.to_s == 'VariableName'

    @variable_name = variable_name
    @content_type = @variable_name.content_type
    @shape = my_shape
    @constant = false
    @warnings = []
    @valref = :value
    @subscripts = normalize_subscripts(subscripts)
    @wrapped_subscripts = wrapped_subscripts
    @variable = true
    @operand = true
    @precedence = 10
    @arg_types = nil
    @arg_shapes = []
    @arg_consts = []
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      types = type_stack[-1]

      @arg_types = type_stack.pop if types.class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      shapes = shape_stack[-1]
      @arg_shapes = shape_stack.pop if shapes.class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    constant_stack.push(@constant)
  end

  def hash
    @variable_name.hash && @subscripts.hash
  end

  def eql?(other)
    @variable_name == other.name && @subscripts == other.subscripts
  end

  def ==(other)
    @variable_name == other.name && @subscripts == other.subscripts
  end

  def signature
    sig = make_signature(@arg_types, @arg_shapes)
    sig += Sigils.make_shape_sigil(@shape) if sig.empty?
    sig
  end

  def dump
    result = Sigils.make_type_sigil(@content_type) + Sigils.make_shape_sigil(@shape)
    "#{self.class}:#{@variable_name}#{signature} -> #{result}"
  end

  def name
    @variable_name
  end

  def constant?
    @constant
  end

  def dimensions?
    !@subscripts.empty?
  end

  def dimensions
    @subscripts
  end

  def compatible?(value)
    numerics = %i[numeric integer]
    strings = %i[string]

    case content_type
    when :numeric, :integer
      numerics.include?(value.content_type)
    when :string
      strings.include?(value.content_type)
    else
      false
    end
  end

  def to_s
    if subscripts.empty?
      @variable_name.to_s
    else
      "#{@variable_name}(#{@subscripts.join(',')})"
    end
  end

  def to_v
    to_s
  end

  def to_sw
    if subscripts.empty?
      @variable_name.to_s
    else
      "#{@variable_name}(#{@wrapped_subscripts.join(',')})"
    end
  end

  def evaluate(interpreter, stack)
    x = false
    x = evaluate_value(interpreter, stack) if @valref == :value
    x = evaluate_ref(interpreter, stack) if @valref == :reference
    x
  end

  private

  def evaluate_value(interpreter, stack)
    x = nil
    x = evaluate_value_scalar(interpreter, stack) if @shape == :scalar
    x = evaluate_value_array(interpreter, stack) if @shape == :array
    x = evaluate_value_matrix(interpreter, stack) if @shape == :matrix
    x
  end

  def evaluate_ref(interpreter, stack)
    x = nil
    x = evaluate_ref_scalar(interpreter, stack) if @shape == :scalar

    x = evaluate_ref_compound(interpreter, stack) if
      @shape == :array || @shape == :matrix
    x
  end

  def normalize_subscripts(subscripts)
    raise(BASICSyntaxError, 'Invalid subscripts container') unless
      subscripts.class.to_s == 'Array'

    int_subscripts = []
    subscripts.each do |subscript|
      raise(BASICExpressionError, "Invalid subscript #{subscript}") unless
        subscript.numeric_constant?

      int_subscripts << subscript.truncate
    end

    int_subscripts
  end

  # return a single value
  def evaluate_value_scalar(interpreter, stack)
    if previous_is_array(stack)
      subscripts = get_subscripts(stack)
      @subscripts = interpreter.normalize_subscripts(subscripts)

      @wrapped_subscripts =
        interpreter.wrap_subscripts(@variable_name, @subscripts)

      interpreter.check_subscripts(@variable_name, @subscripts,
                                   @wrapped_subscripts)
    end

    interpreter.get_value(self)
  end

  def get_subscripts(stack)
    subscripts = stack.pop

    if subscripts.empty?
      raise(BASICExpressionError,
            'Variable expects subscripts, found empty parentheses')
    end

    subscripts
  end

  def evaluate_value_array(interpreter, _)
    dims = interpreter.get_dimensions(@variable_name)

    msg = "Variable #{@variable_name} has no dimensions"
    raise BASICExpressionError, msg if dims.nil?

    msg = "Array #{@variable_name} requires one dimension"
    raise BASICExpressionError, msg if dims.size != 1

    values = evaluate_value_array_1(interpreter, dims[0].to_i)
    BASICArray.new(dims, values)
  end

  def evaluate_value_array_1(interpreter, n_cols)
    values = {}

    base = $options['base'].value

    (base..n_cols).each do |col|
      coords = AbstractElement.make_coord(col)
      wcoords = interpreter.wrap_subscripts(@variable_name, coords)
      variable = Variable.new(@variable_name, :array, coords, wcoords)
      values[coords] = interpreter.get_value(variable)
    end

    values
  end

  def evaluate_value_matrix(interpreter, _)
    dims = interpreter.get_dimensions(@variable_name)

    msg = "Variable #{@variable_name} has no dimensions"
    raise BASICExpressionError, msg if dims.nil?

    # msg = "Matrix #{@variable_name} requires two dimensions"
    # don't check this; it causes problems for special forms
    # raise BASICExpressionError.new(msg) if dims.size != 2

    values = evaluate_matrix_n(interpreter, dims)
    Matrix.new(dims, values)
  end

  def evaluate_matrix_n(interpreter, dims)
    values = {}

    values = evaluate_matrix_1(interpreter, dims[0].to_i) if
      dims.size == 1

    values = evaluate_matrix_2(interpreter, dims[0].to_i, dims[1].to_i) if
      dims.size == 2

    values
  end

  def evaluate_matrix_1(interpreter, n_cols)
    values = {}

    base = $options['base'].value

    (base..n_cols).each do |col|
      coords = AbstractElement.make_coord(col)
      wcoords = interpreter.wrap_subscripts(@variable_name, coords)
      variable = Variable.new(@variable_name, :matrix, coords, wcoords)
      values[coords] = interpreter.get_value(variable)
    end

    values
  end

  def evaluate_matrix_2(interpreter, n_rows, n_cols)
    values = {}

    base = $options['base'].value

    (base..n_rows).each do |row|
      (base..n_cols).each do |col|
        coords = AbstractElement.make_coords(row, col)
        wcoords = interpreter.wrap_subscripts(@variable_name, coords)
        variable = Variable.new(@variable_name, :matrix, coords, wcoords)
        values[coords] = interpreter.get_value(variable)
      end
    end

    values
  end

  # return a single value, a reference to this object
  def evaluate_ref_scalar(interpreter, stack)
    if previous_is_array(stack)
      subscripts = stack.pop
      @subscripts = interpreter.normalize_subscripts(subscripts)
      num_args = @subscripts.length

      @wrapped_subscripts =
        interpreter.wrap_subscripts(@variable_name, @subscripts)

      if num_args.zero?
        raise(BASICExpressionError,
              'Variable expects subscripts, found empty parentheses')
      end

      interpreter.check_subscripts(@variable_name, @subscripts,
                                   @wrapped_subscripts)
    end

    self
  end

  # return a single value, a reference to this object
  def evaluate_ref_compound(interpreter, stack)
    if previous_is_array(stack)
      subscripts = stack.pop
      @subscripts = interpreter.normalize_subscripts(subscripts)
      num_args = @subscripts.length

      @wrapped_subscripts =
        interpreter.wrap_subscripts(@variable_name, @subscripts)

      if num_args.zero?
        raise(BASICExpressionError,
              'Variable expects subscripts, found empty parentheses')
      end

      unless @set_dims
        interpreter.check_subscripts(@variable_name, @subscripts,
                                     @wrapped_subscripts)
      end
    end

    self
  end
end

# Class for declaration (in a DIM statement)
class Declaration < AbstractElement
  attr_reader :subscripts, :content_type, :shape, :warnings

  def initialize(variable_name)
    super()

    raise(BASICSyntaxError, "'#{variable_name}' is not a variable name") unless
      variable_name.class.to_s == 'VariableName'

    @variable_name = variable_name
    @subscripts = []
    @variable = true
    @content_type = @variable_name.content_type
    @shape = :unknown
    @warnings = []
    @arg_types = []
    @arg_shapes = []
    @arg_consts = []
  end

  def name
    @variable_name
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    raise(BASICExpressionError, "Bad expression #{@name}") if
      shape_stack.empty?

    raise(BASICExpressionError, "Bad expression #{@name} #{shapes}") unless
      shape_stack[-1].class.to_s == 'Array'

    @arg_shapes = shape_stack.pop

    @shape = :scalar
    @shape = :array if @arg_shapes.size == 1
    @shape = :matrix if @arg_shapes.size == 2

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    constant_stack.push(@constant)
  end

  def signature
    Sigils.make_shape_sigil(@shape)
  end

  def dump
    result = Sigils.make_type_sigil(@content_type) + Sigils.make_shape_sigil(@shape)
    "#{self.class}:#{@variable_name}#{signature} -> #{result}"
  end

  def constant?
    @constant
  end

  def to_s
    if subscripts.empty?
      @variable_name.to_s
    else
      "#{@variable_name}(#{@subscripts.join(',')})"
    end
  end

  # return a single value, a reference to this object
  def evaluate(_, stack)
    if previous_is_array(stack)
      @subscripts = stack.pop
      num_args = @subscripts.length

      if num_args.zero?
        raise(BASICExpressionError,
              'Variable expects subscripts, found empty parentheses')
      end
    end

    self
  end
end

# A list (needed because it has precedence value)
class ExpressionList < AbstractElement
  attr_reader :expressions, :warnings

  def initialize(expressions)
    super()

    @list = true
    @expressions = expressions
    @warnings = []
    @variable = true
    @precedence = 10
  end

  def dump
    lines = []

    @expressions.each { |expression| lines.concat expression.dump }

    lines
  end

  def content_type
    types = []

    @expressions.each { |expression| types << expression.content_type }

    types
  end

  def set_content_type(type_stack)
    @expressions.each(&:set_content_type)

    type_stack.push(content_type)
  end

  def shape
    shapes = []

    @expressions.each { |expression| shapes << expression.shape }

    shapes
  end

  def set_shape(shape_stack)
    @expressions.each(&:set_shape)

    shape_stack.push(shape)
  end

  def constant?
    constants = []

    @expressions.each { |expression| constants << expression.constant? }

    constants
  end

  def set_constant(constant_stack)
    @expressions.each(&:set_constant)

    constant_stack.push(constant?)
  end

  def evaluate(interpreter, _)
    interpreter.evaluate(@expressions)
  end

  def to_s
    "[#{@expressions.join('] [')}]"
  end

  def size
    @expressions.size
  end

  def count
    @expressions.count
  end
end

# class to hold REM text
class Remark < AbstractElement
  def initialize(tokens)
    super()

    @texts = []
    @texts = tokens.map(&:to_s) unless tokens.nil?
  end

  def dump
    "#{self.class}:#{@texts.join}"
  end
end
