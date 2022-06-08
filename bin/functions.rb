# frozen_string_literal: true

# function (provides a result)
class AbstractFunction < AbstractElement
  attr_reader :name, :default_shape, :content_type, :shape, :constant, :warnings

  def initialize(text)
    super()

    @name = text
    @function = true
    @default_shape = :unknown
    @content_type = :numeric
    @content_type = :string if @name.to_s[-1] == '$'
    @content_type = :integer if @name.to_s[-1] == '%'
    @shape = nil
    @constant = false
    @warnings = []
    @valref = :value
    @operand = true
    @precedence = 10
    @arg_types = nil
    @arg_shapes = []
    @arg_consts = []
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      types = type_stack.pop

      raise(BASICExpressionError, "Bad expression #{@name} #{types}") unless
        types.class.to_s == 'Array'

      @arg_types = types
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      shapes = shape_stack.pop

      raise(BASICExpressionError, "Bad expression #{@name} #{shapes}") unless
        shapes.class.to_s == 'Array'

      @arg_shapes = shapes
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      constants = constant_stack.pop

      raise(BASICExpressionError, "Bad expression #{@name} #{constants}") unless
        constants.class.to_s == 'Array'

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def sigils
    make_sigils(@arg_types, @arg_shapes)
  end

  def signature
    sigils = make_sigils(@arg_types, @arg_shapes)

    UserFunctionSignature.new(@name, sigils)
  end

  def pop_stack(stack)
    stack.pop
  end

  def dump
    result = make_type_sigil(@content_type) + make_shape_sigil(@shape)
    const = @constant ? '=' : ''
    "#{self.class}:#{signature} -> #{const}#{result}"
  end

  def to_s
    @name
  end

  def value?
    @valref == :value
  end

  def reference?
    @valref == :reference
  end

  private

  def default_args(interpreter)
    arg = interpreter.default_args(@name)

    raise(BASICSyntaxError, "#{@name} requires arguments") if arg.nil?

    arg
  end

  def counts_to_text(counts)
    words = %w[zero one two]
    texts = counts.map { |v| words[v] }
    texts.join(' or ')
  end

  def match_arg_type(value, type)
    case type
    when :numeric
      value.numeric_constant?
    when :string
      value.text_constant?
    when :integer
      value.numeric_constant?
    when :boolean
      value.boolean_constant?
    else
      false
    end
  end

  def match_arg_shape(value, shape)
    case shape
    when :scalar
      value.scalar?
    when :array
      value.array?
    when :matrix
      value.matrix?
    else
      false
    end
  end

  def match_arg_type_shape(value, spec)
    type = spec['type']
    type_compatible = match_arg_type(value, type)

    my_shape = spec['shape']
    shape_compatible = match_arg_shape(value, my_shape)

    type_compatible && shape_compatible
  end

  def match_args_to_signature(args, specs)
    n_args = 0
    n_args = args.size if args.class.to_s == 'Array'

    n_specs = specs.size

    return false if n_args != n_specs

    compatible = true
    (0..n_specs - 1).each do |i|
      compatible &&= match_arg_type_shape(args[i], specs[i])
    end

    compatible
  end

  def check_square(dims)
    raise(BASICSyntaxError, "#{@name} requires matrix") unless dims.size == 2

    raise BASICRuntimeError.new(:te_mat_no_sq, @name) unless
      dims[1] == dims[0]
  end
end

# signature for user-defined function
class UserFunctionSignature < AbstractElement
  attr_reader :name, :sigils

  def initialize(name, sigils)
    @name = name
    @sigils = sigils
  end

  def eql?(other)
    @name == other.name && @sigils == other.sigils
  end

  def hash
    @name.hash + @sigils.hash
  end

  def ==(other)
    return false if other.nil?

    @name == other.name && @sigils == other.sigils
  end

  def !=(other)
    return true if other.nil?

    @name != other.name || @sigils != other.sigils
  end

  def to_s
    @name.to_s + XrefEntry.format_sigils(@sigils)
  end

  def to_sw
    to_s
  end

  def scalar?
    true
  end

  def content_type
    @name.content_type
  end

  def compatible?(value)
    numerics = %i[numeric integer]
    strings = %i[string]

    case content_type
    when :numeric
      numerics.include?(value.content_type)
    when :string
      strings.include?(value.content_type)
    when :integer
      numerics.include?(value.content_type)
    else
      false
    end
  end
end

# User-defined function (provides a scalar value)
class UserFunction < AbstractFunction
  attr_writer :valref, :set_dims

  def self.accept?(token)
    classes = %w[UserFunctionToken]
    classes.include?(token.class.to_s)
  end

  def initialize(text)
    super

    @user_function = true
    @shape = :scalar
    @constant = false
    @default_shape = :scalar
  end

  def to_sw
    @name.to_s
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # user function is never const, as it can be re-assigned
    @constant = false

    constant_stack.push(@constant)
  end

  def compatible?(value)
    numerics = %i[numeric integer]
    strings = %i[string]

    case content_type
    when :numeric
      numerics.include?(value.content_type)
    when :string
      strings.include?(value.content_type)
    when :integer
      numerics.include?(value.content_type)
    else
      false
    end
  end

  def destinations(user_function_start_lines)
    line_number_stmt_mod = user_function_start_lines[signature]

    return [] if line_number_stmt_mod.nil?

    line_number = line_number_stmt_mod.line_number
    stmt = line_number_stmt_mod.statement
    [TransferRefLineStmt.new(line_number, stmt, :function)]
  end

  def to_s
    @name.to_s
  end

  def evaluate(interpreter, arg_stack)
    return @cached unless @cached.nil?

    res = false
    res = evaluate_value(interpreter, arg_stack) if @valref == :value
    res = evaluate_ref(interpreter, arg_stack) if @valref == :reference

    @cached = res if @constant && $options['cache_const_expr']
    res
  end

  private

  def evaluate_value(interpreter, arg_stack)
    arguments = arg_stack.pop
    sigils = XrefEntry.make_sigils(arguments)
    signature = UserFunctionSignature.new(@name, sigils)
    definition = interpreter.get_user_function(signature)

    # dummy variable names and their (now known) values
    params = definition.arguments
    param_names_values = params.zip(arguments)
    names_and_values = param_names_values.to_h
    interpreter.define_user_var_values(names_and_values)

    begin
      expression = definition.expression
      if expression.nil?
        signature = UserFunctionSignature.new(@name, sigils)
        interpreter.run_user_function(signature)

        results = [interpreter.get_value(signature)]
      else
        results = expression.evaluate(interpreter)
      end
    rescue BASICRuntimeError => e
      interpreter.clear_user_var_values

      raise e
    end

    interpreter.clear_user_var_values
    results[0]
  end

  def evaluate_ref(interpreter, arg_stack)
    x = nil
    x = evaluate_ref_scalar(interpreter, arg_stack) if
      @default_shape == :scalar

    x = evaluate_ref_compound(interpreter, arg_stack) if
      @default_shape == :array || @default_shape == :matrix
    x
  end

  # return a single value, a reference to this object
  def evaluate_ref_scalar(_interpreter, arg_stack)
    raise BASICSyntaxError, 'function evaluated with arguments' if
      previous_is_array(arg_stack)

    self
  end

  # return a single value, a reference to this object
  def evaluate_ref_compound(_interpreter, arg_stack)
    raise BASICSyntaxError, 'function evaluated with arguments' if
      previous_is_array(arg_stack)

    self
  end
end

# function ABS
class FunctionAbs < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].abs

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ASCII, ASCII%, ASC
class FunctionAscii < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    text = args[0].to_v

    raise BASICRuntimeError.new(:te_str_empty, @name) if text.empty?

    value = text[0].ord

    raise BASICRuntimeError.new(:te_val_out, @name) unless
      value.between?(32, 126) || $options['asc_allow_all'].value

    res = if content_type == :integer
            IntegerValue.new(value)
          else
            NumericValue.new(value)
          end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ARCCOS
class FunctionArcCos < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].arccos

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ARCSIN
class FunctionArcSin < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].arcsin

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ARCTAN
class FunctionArcTan < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature1)
      res = args[0].atn
    elsif match_args_to_signature(args, @signature2)
      res = args[0].atn2(args[1])
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function AVG
class FunctionAvg < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    sum = args[0].sum / args[0].size
    res = NumericValue.new(sum)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function CHR$
class FunctionChr < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    value = args[0].to_i

    raise BASICRuntimeError.new(:te_val_out, @name) unless
      value.between?(32, 126) || $options['chr_allow_all'].value

    res = TextValue.new(value.chr)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function CON1
class FunctionCon1 < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = NumericValue.new(1)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.make_array(dims, new_value)
      res = BASICArray.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function CON1%
class FunctionCon1I < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = IntegerValue.new(1)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.make_array(dims, new_value)
      res = BASICArray.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function CON1$
class FunctionCon1T < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature0 = [
      { 'type' => :string, 'shape' => :scalar }
    ]
    @signature1 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature0)
      args0 = default_args(interpreter)
      dims = args0.clone
      new_value = args[0]
      values = BASICArray.make_array(dims, new_value)
      res = BASICArray.new(dims, values)
    elsif match_args_to_signature(args, @signature1)
      dims = [args[0]]
      new_value = args[1]
      values = BASICArray.make_array(dims, new_value)
      res = BASICArray.new(dims, values)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function CON, CON2
class FunctionCon2 < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = NumericValue.new(1)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.make_array(dims, new_value) if dims.size == 1
      values = Matrix.make_matrix(dims, new_value) if dims.size == 2
      res = Matrix.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function CON2%
class FunctionCon2I < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = IntegerValue.new(1)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.make_array(dims, new_value) if dims.size == 1
      values = Matrix.make_matrix(dims, new_value) if dims.size == 2
      res = Matrix.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function CON2$
class FunctionCon2T < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :scalar
    @signature0 = [
      { 'type' => :string, 'shape' => :scalar }
    ]
    @signature1 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
    @signature2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature0)
      args0 = default_args(interpreter)
      dims = args0.clone
      new_value = args[0]
      values = Matrix.make_array(dims, new_value) if dims.size == 1
      values = Matrix.make_matrix(dims, new_value) if dims.size == 2
      res = Matrix.new(dims, values)
    elsif match_args_to_signature(args, @signature1)
      dims = [args[0], args[0]]
      new_value = args[1]
      values = Matrix.make_array(dims, new_value) if dims.size == 1
      values = Matrix.make_matrix(dims, new_value) if dims.size == 2
      res = Matrix.new(dims, values)
    elsif match_args_to_signature(args, @signature2)
      dims = [args[0], args[1]]
      new_value = args[2]
      values = Matrix.make_array(dims, new_value) if dims.size == 1
      values = Matrix.make_matrix(dims, new_value) if dims.size == 2
      res = Matrix.new(dims, values)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function COS
class FunctionCos < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].cos

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function COT
class FunctionCot < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].cot

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function CSC
class FunctionCsc < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].csc

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function DEG
class FunctionDeg < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].to_degrees

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function DET
class FunctionDet < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :matrix
    @signature1 = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].determinant

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ERL
class FunctionErl < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # ERL() is never constant

    constant_stack.push(@constant)
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        arg = NumericValue.new(0)
        res = interpreter.error_line(arg)
      elsif match_args_to_signature(args, @signature1)
        res = interpreter.error_line(args[0])
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      arg = NumericValue.new(0)
      res = interpreter.error_line(arg)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ERR
class FunctionErr < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar
    @constant = false

    @default_shape = :scalar
    @signature0 = []
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # ERR() is never constant

    constant_stack.push(@constant)
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        res = interpreter.error_code
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      res = interpreter.error_code
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function EXP
class FunctionExp < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].exp

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function FIX, FIX%
class FunctionFix < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = if content_type == :integer
            args[0].floor.to_int
          else
            args[0].floor
          end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function FRAC
class FunctionFrac < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    a0int = args[0].truncate
    res = args[0].subtract(a0int)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function IDN
class FunctionIdn < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.identity_values(dims)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = [args[0]] * 2
        values = Matrix.identity_values(dims)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        raise BASICRuntimeError.new(:te_mat_no_sq, @name) unless
          args[1] == args[0]

        dims = args.clone
        values = Matrix.identity_values(dims)
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)

      raise BASICRuntimeError.new(:te_mat_no_sq, @name) unless
        args.size == 2 && args[1] == args[0]

      dims = args.clone
      values = Matrix.identity_values(dims)
      res = Matrix.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function INSTR, INSTR%
class FunctionInstr < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature2 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
    @signature3 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature2)
      start = 1
      value = args[0].to_v
      search = args[1].to_v
    elsif match_args_to_signature(args, @signature3)
      start = args[0].to_i
      value = args[1].to_v
      search = args[2].to_v
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    raise BASICRuntimeError.new(:te_val_out, @name) if start < 1

    start -= 1
    index = value.index(search, start)

    if index.nil?
      index = 0
    else
      index += 1
    end

    res = if content_type == :integer
            IntegerValue.new(index)
          else
            NumericValue.new(index)
          end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function INT, INT%
class FunctionInt < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 = [{ 'type' => :boolean, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature1)
      res = $options['int_floor'].value ? args[0].floor : args[0].truncate
    elsif match_args_to_signature(args, @signature2)
      res = $options['int_floor'].value ? args[0].to_numeric.floor : args[0].to_numeric.truncate
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
    res = res.to_int if @content_type == :integer

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function INV
class FunctionInv < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :matrix
    @signature1 = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    dims = args[0].dimensions
    check_square(dims)
    res = Matrix.new(dims.clone, args[0].inverse_values)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function LEFT$
class FunctionLeft < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature2 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature2)

    value = args[0].to_v
    count = args[1].to_i

    raise BASICRuntimeError.new(:te_count_inv, @name) if count.negative?

    if count.positive?
      count2 = count - 1
      text = value[0..count2]
    else
      text = ''
    end

    res = TextValue.new(text)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function LEN
class FunctionLen < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    text = args[0].to_v
    res = NumericValue.new(text.size)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function LOG
class FunctionLog < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature1)
      res = args[0].log
    elsif match_args_to_signature(args, @signature2)
      res = args[0].logb(args[1])
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function LOWER$
class FunctionLowerT < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].lower

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MAXA
class FunctionMaxA < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].max

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MAXA%
class FunctionMaxAI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :integer, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].max_i

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MAXA$
class FunctionMaxAT < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :string, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].max_t

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MAXM
class FunctionMaxM < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :matrix
    @signature1 = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].max

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MAXM%
class FunctionMaxMI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :matrix
    @signature1 = [{ 'type' => :integer, 'shape' => :matrix }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].max_i

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MAXM$
class FunctionMaxMT < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :matrix
    @signature1 = [{ 'type' => :string, 'shape' => :matrix }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].max_t

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MEDIAN
class FunctionMedian < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_intepreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    med = args[0].median_average
    res = NumericValue.new(med)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MEDIAN%, MEDIAN$
class FunctionMedianIT < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => @content_type, 'shape' => :array }]
  end

  def evaluate(_intepreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    med = args[0].median_lesser
    res = IntegerValue.new(med) if @content_type == :integer
    res = TextValue.new(med) if @content_type == :string

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MID$
class FunctionMid < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature3 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature3)

    value = args[0].to_v
    start = args[1].to_i
    length = args[2].to_i

    raise BASICRuntimeError.new(:te_count_inv, @name) if start < 1

    raise BASICRuntimeError.new(:te_len_inv, @name) if length.negative?

    if length.positive?
      start_index = start - 1
      end_index = start_index + length - 1

      text = value[start_index..end_index]
      text = '' if text.nil?
    else
      text = ''
    end

    res = TextValue.new(text)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MINA
class FunctionMinA < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].min

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MINA%
class FunctionMinAI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :integer, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].min_i

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MINA$
class FunctionMinAT < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :string, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].min_t

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MINM
class FunctionMinM < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :matrix
    @signature1 = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].min

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MINM%
class FunctionMinMI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :matrix
    @signature1 = [{ 'type' => :integer, 'shape' => :matrix }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].min_i

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MINM$
class FunctionMinMT < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :matrix
    @signature1 = [{ 'type' => :string, 'shape' => :matrix }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    raise BASICRunTimeError.new(:te_too_few, @name) if
      args[0].empty?

    res = args[0].min_t

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function MOD
class FunctionMod < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  # return a single value
  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature2)

    res = args[0].mod(args[1])

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function NCOL, NCOL%
class FunctionNcol < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :matrix
    @signature1 = [{ 'type' => :numeric, 'shape' => :matrix }]
    @signature2 = [{ 'type' => :integer, 'shape' => :matrix }]
    @signature3 = [{ 'type' => :string, 'shape' => :matrix }]
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # NCOL() is never constant

    res = constant_stack.push(@constant)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1) ||
      match_args_to_signature(args, @signature2) ||
      match_args_to_signature(args, @signature3)

    res = if content_type == :integer
            IntegerValue.new(args[0].ncol)
          else
            NumericValue.new(args[0].ncol)
          end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function NELEM, NELEM%
class FunctionNelem < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :numeric, 'shape' => :array }]
    @signature2 = [{ 'type' => :integer, 'shape' => :array }]
    @signature3 = [{ 'type' => :string, 'shape' => :array }]
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # NELEM() is never constant

    res = constant_stack.push(@constant)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1) ||
      match_args_to_signature(args, @signature2) ||
      match_args_to_signature(args, @signature3)

    res = if content_type == :integer
            IntegerValue.new(args[0].size)
          else
            NumericValue.new(args[0].size)
          end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function NROW
class FunctionNrow < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :matrix
    @signature1 = [{ 'type' => :numeric, 'shape' => :matrix }]
    @signature2 = [{ 'type' => :integer, 'shape' => :matrix }]
    @signature3 = [{ 'type' => :string, 'shape' => :matrix }]
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # NROW() is never constant

    res = constant_stack.push(@constant)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1) ||
      match_args_to_signature(args, @signature2) ||
      match_args_to_signature(args, @signature3)

    res = if content_type == :integer
            IntegerValue.new(args[0].nrow)
          else
            NumericValue.new(args[0].nrow)
          end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function NUM
class FunctionNum < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_ts = [{ 'type' => :string, 'shape' => :scalar }]
    @signature_bs = [{ 'type' => :boolean, 'shape' => :scalar }]
    @signature_is = [{ 'type' => :integer, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature_ts)
      f = args[0].to_v.to_f
    elsif match_args_to_signature(args, @signature_bs)
      f = args[0].to_f
    elsif match_args_to_signature(args, @signature_is)
      f = args[0].to_v.to_f
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    res = NumericValue.new(f)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function PACK$
class FunctionPack < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    array = args[0]
    dims = array.dimensions

    raise(BASICSyntaxError, "#{@name} requires array") unless dims.size == 1

    res = array.pack

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function PROD
class FunctionProd < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    sum = args[0].prod
    res = NumericValue.new(sum)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RAD
class FunctionRad < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].to_radians

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RIGHT$
class FunctionRight < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature2 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature2)

    value = args[0].to_v
    count = args[1].to_i

    raise BASICRuntimeError.new(:te_count_inv, @name) if count.negative?

    start = value.size - count
    start = 0 if start.negative?
    res = TextValue.new(value[start..-1])

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ROUND
class FunctionRound < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature2)

    res = args[0].round(args[1])

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RND
class FunctionRnd < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # RND() is never constant

    constant_stack.push(@constant)
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        arg = default_args(interpreter)
        res = NumericValue.new_rand(interpreter, arg)
      elsif match_args_to_signature(args, @signature1)
        res = NumericValue.new_rand(interpreter, args[0])
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      arg = default_args(interpreter)
      res = NumericValue.new_rand(interpreter, arg)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RND%
class FunctionRndI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :integer, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # RND%() is never constant

    constant_stack.push(@constant)
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        arg = default_args(interpreter)
        res = IntegerValue.new_rand(interpreter, arg)
      elsif match_args_to_signature(args, @signature1)
        res = IntegerValue.new_rand(interpreter, args[0])
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      arg = default_args(interpreter)
      res = IntegerValue.new_rand(interpreter, arg)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RND$
class FunctionRndT < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
    @signature3 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]

    @sets = {
      'A' => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      'a' => 'abcdefghijklmnopqrstuvwxyz',
      'B' => 'BCDFGHJKLMNPQRSTVWXYZ',
      'b' => 'bcdfghjklmnpqrstvwxyz',
      'C' => 'ACDEFHJKLMNPQRTUVWXY',
      'c' => 'acdefhjklmnpqrtuvwxy',
      '0' => '0123456789',
      '1' => '123456789',
      'X' => '01234567890ABCDEF',
      'x' => '01234567890abcdef'
    }
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # RND$() is never constant

    constant_stack.push(@constant)
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    # assume the set of uppercase alphas
    set = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

    # parameters specify length of string and may change set
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        count = default_args(interpreter)
      elsif match_args_to_signature(args, @signature1)
        count = args[0]
      elsif match_args_to_signature(args, @signature2)
        count = args[0]
        key = args[1].value
        set = key
        set = @sets[key] if @sets.include?(key)
      elsif match_args_to_signature(args, @signature3)
        count = args[0]
        key = args[1].value
        set = key + args[2].value
        set = @sets[key] + args[2].value if @sets.include?(key)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      count = default_args(interpreter)
    end

    length = count.to_i

    res = TextValue.new_rand(interpreter, length, set)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RND1
class FunctionRnd1 < AbstractFunction
  def initialize(text)
    super

    @shape = :array
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # RND1() is never constant

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    upper_bound = NumericValue.new(1)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.rnd_values(dims, interpreter, upper_bound)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = BASICArray.rnd_values(dims, interpreter, upper_bound)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = [args[0]]
        upper_bound = args[1]
        values = BASICArray.rnd_values(dims, interpreter, upper_bound)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.rnd_values(dims, interpreter, upper_bound)
      res = BASICArray.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RND1%
class FunctionRnd1I < AbstractFunction
  def initialize(text)
    super

    @shape = :array
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :integer, 'shape' => :scalar }]
    @signature2 = [
      { 'type' => :integer, 'shape' => :scalar },
      { 'type' => :integer, 'shape' => :scalar }
    ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # RND1%() is never constant

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    upper_bound = IntegerValue.new(100)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.rndi_values(dims, interpreter, upper_bound)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = BASICArray.rndi_values(dims, interpreter, upper_bound)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = [args[0]]
        upper_bound = args[1]
        values = BASICArray.rndi_values(dims, interpreter, upper_bound)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.rndi_values(dims, interpreter, upper_bound)
      res = BASICArray.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RND1$
class FunctionRnd1T < AbstractFunction
  def initialize(text)
    super

    @shape = :array
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :integer, 'shape' => :scalar }]
    @signature2 = [
      { 'type' => :integer, 'shape' => :scalar },
      { 'type' => :integer, 'shape' => :scalar }
    ]
    @signature3 = [
      { 'type' => :integer, 'shape' => :scalar },
      { 'type' => :integer, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
    @signature4 = [
      { 'type' => :integer, 'shape' => :scalar },
      { 'type' => :integer, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]

    @sets = {
      'A' => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      'a' => 'abcdefghijklmnopqrstuvwxyz',
      'B' => 'BCDFGHJKLMNPQRSTVWXYZ',
      'b' => 'bcdfghjklmnpqrstvwxyz',
      'C' => 'ACDEFHJKLMNPQRTUVWXY',
      'c' => 'acdefhjklmnpqrtuvwxy',
      '0' => '0123456789',
      '1' => '123456789',
      'X' => '01234567890ABCDEF',
      'x' => '01234567890abcdef'
    }
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # RND1() is never constant

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    length = 6
    set = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.rndt_values(dims, interpreter, length, set)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = BASICArray.rndt_values(dims, interpreter, length, set)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = [args[0]]
        length = args[1].to_i
        values = BASICArray.rndt_values(dims, interpreter, length, set)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature3)
        dims = [args[0]]
        length = args[1].to_i
        key = args[2].value
        set = key
        set = @sets[key] if @sets.include?(key)
        values = BASICArray.rndt_values(dims, interpreter, length, set)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature4)
        dims = [args[0]]
        length = args[1].to_i
        key = args[2].value
        extras = args[3].value
        set = key + extras
        set = @sets[key] + extras if @sets.include?(key)
        values = BASICArray.rndt_values(dims, interpreter, length, set)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.rndt_values(dims, interpreter, length, set)
      res = BASICArray.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RND2
class FunctionRnd2 < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
    @signature3 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # RND2() is never constant

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    upper_bound = NumericValue.new(1)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.rnd_values(dims, interpreter, upper_bound)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = Matrix.rnd_values(dims, interpreter, upper_bound)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = args.clone
        values = Matrix.rnd_values(dims, interpreter, upper_bound)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature3)
        dims = args.clone[0..1]
        upper_bound = args[2]
        values = Matrix.rnd_values(dims, interpreter, upper_bound)
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.rnd_values(dims, interpreter, upper_bound)
      res = Matrix.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RND2%
class FunctionRnd2I < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :integer, 'shape' => :scalar }]
    @signature2 =
      [
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar }
      ]
    @signature3 =
      [
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # RND2%() is never constant

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    upper_bound = IntegerValue.new(100)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.rndi_values(dims, interpreter, upper_bound)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = Matrix.rndi_values(dims, interpreter, upper_bound)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = args.clone
        values = Matrix.rndi_values(dims, interpreter, upper_bound)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature3)
        dims = args.clone[0..1]
        upper_bound = args[2]
        values = Matrix.rndi_values(dims, interpreter, upper_bound)
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.rndi_values(dims, interpreter, upper_bound)
      res = Matrix.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function RND2$
class FunctionRnd2T < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix
    @constant = false

    @default_shape = :scalar
    @signature0 = []
    @signature2 =
      [
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar }
      ]
    @signature3 =
      [
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar }
      ]
    @signature4 =
      [
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :string, 'shape' => :scalar }
      ]
    @signature5 =
      [
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :integer, 'shape' => :scalar },
        { 'type' => :string, 'shape' => :scalar },
        { 'type' => :string, 'shape' => :scalar }
      ]

    @sets = {
      'A' => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      'a' => 'abcdefghijklmnopqrstuvwxyz',
      'B' => 'BCDFGHJKLMNPQRSTVWXYZ',
      'b' => 'bcdfghjklmnpqrstvwxyz',
      'C' => 'ACDEFHJKLMNPQRTUVWXY',
      'c' => 'acdefhjklmnpqrtuvwxy',
      '0' => '0123456789',
      '1' => '123456789',
      'X' => '01234567890ABCDEF',
      'x' => '01234567890abcdef'
    }
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # RND2$() is never constant

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    length = 6
    set = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.rndt_values(dims, interpreter, length, set)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = args.clone
        values = Matrix.rndt_values(dims, interpreter, length, set)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature3)
        dims = args.clone[0..1]
        length = args[2].to_i
        values = Matrix.rndt_values(dims, interpreter, length, set)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature4)
        dims = args.clone[0..1]
        length = args[2].to_i
        key = args[3].value
        set = key
        set = @sets[key] if @sets.include?(key)
        values = Matrix.rndt_values(dims, interpreter, length, set)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature5)
        dims = args.clone[0..1]
        length = args[2].to_i
        key = args[3].value
        extras = args[4].value
        set = key + extras
        set = @sets[key] + extras if @sets.include?(key)
        values = Matrix.rndt_values(dims, interpreter, length, set)
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.rndt_values(dims, interpreter, length, set)
      res = Matrix.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function REV1, REV1%, REV1$
class FunctionRev1 < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :array
    @signature1 = [{ 'type' => @content_type, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    dims = args[0].dimensions
    res = BASICArray.new(dims, args[0].reverse_values)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SEC
class FunctionSec < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].sec

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SGN, SGN%
class FunctionSgn < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].sign

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SIN
class FunctionSin < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].sin

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SORT1, SORT1%, SORT1$
class FunctionSort1 < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :array
    @signature1 = [{ 'type' => @content_type, 'shape' => :array }]
  end

  def evaluate(_intepreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    values = args[0].sort_values
    dims = args[0].dimensions
    res = BASICArray.new(dims, values)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SORT2, SORT2%, SORT2$
class FunctionSort2 < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :matrix
    @signature1 = [{ 'type' => @content_type, 'shape' => :matrix }]
  end

  def evaluate(_intepreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    values = args[0].sort_values
    dims = args[0].dimensions
    res = Matrix.new(dims, values)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SPACE$, SPC$
class FunctionSpace < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    width = args[0].to_v

    spaces = if width.positive?
               ' ' * width
             else
               # zero or negative value yields empty string
               ''
             end

    res = TextValue.new(spaces)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SPLIT1$
class FunctionSplit1T < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature1 = [{ 'type' => :string, 'shape' => :scalar }]
    @signature2 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
    @signature3 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :integer, 'shape' => :scalar }
    ]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature1)
      t = args[0].to_v
      ts = t.split
    elsif match_args_to_signature(args, @signature2)
      t = args[0].to_v
      s = args[1].to_v
      ts = t.split(s)
    elsif match_args_to_signature(args, @signature3)
      t = args[0].to_v
      s = args[1].to_v
      m = args[2].to_i
      ts = t.split(s, m)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    base = $options['base'].value

    upper = ts.size - (1 - base)
    u_dim = NumericValue.new(upper)

    dims = [u_dim]

    values = {}

    (base..dims[0].to_i).each_with_index do |col, index|
      coords = AbstractElement.make_coord(col)
      values[coords] = TextValue.new(ts[index])
    end

    res = BASICArray.new(dims, values)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SQR
class FunctionSqr < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].sqrt

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function STR$
class FunctionStr < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  # return a single value
  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature1)
      res = TextValue.new(args[0].to_s)
    elsif match_args_to_signature(args, @signature2)
      places = args[1].to_i
      value = args[0].to_f
      text = format('%.*f', places, value)
      res = TextValue.new(text)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function STRING$
class FunctionString < AbstractFunction
  def initialize(text)
    super

    @content_type = :string
    @shape = :scalar

    @default_shape = :scalar
    @signature2 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature2)

    text = args[0].to_v

    raise BASICRuntimeError.new(:te_str_empty, @name) if text.empty?

    char = text[0]

    width = args[1].to_v

    s = if width.positive?
          char * width
        else
          # zero or negative value yields empty string
          ''
        end

    res = TextValue.new(s)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SUM, SUM%
class FunctionSum < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    sum = args[0].sum

    res = if content_type == :integer
            IntegerValue.new(sum)
          else
            NumericValue.new(sum)
          end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function TAB
class FunctionTab < AbstractFunction
  def initialize(text)
    super

    @content_type = :string
    @shape = :scalar
    @constant = false

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constant_stack.pop
    end

    # TAB() is never constant

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    console_io = interpreter.console_io
    width = console_io.columns_to_advance(args[0].to_v)

    spaces = if width.positive?
               ' ' * width
             elsif width.negative?
               "\b" * -width
             else
               ''
             end

    res = TextValue.new(spaces)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function TAN
class FunctionTan < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].tan

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function TIME
class FunctionTime < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar
    @constant = false

    @default_shape = :scalar
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    # ignore argument
    now = Time.now
    start = interpreter.start_time
    result = now - start
    res = NumericValue.new(result)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function TRN
class FunctionTrn < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :matrix
    @signature1 = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    dims = args[0].dimensions
    new_dims = [dims[1], dims[0]]
    res = Matrix.new(new_dims, args[0].transpose_values)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function UNIQ1, UNIQ1%, UNIQ1$
class FunctionUniq1 < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :array
    @signature1 = [{ 'type' => @content_type, 'shape' => :array }]
  end

  def evaluate(_intepreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    values = args[0].unique_values
    dims = [NumericValue.new(values.size)]
    res = BASICArray.new(dims, values)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function UNPACK, UNPACK%
class FunctionUnpack < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    text = args[0]

    res = if content_type == :integer
            text.ia_unpack
          else
            text.na_unpack
          end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function UPPER$
class FunctionUpperT < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = args[0].upper

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function VAL
class FunctionVal < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature1)

    res = NumericValue.new(args[0].to_v.to_f)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ZER1
class FunctionZer1 < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = NumericValue.new(0)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.make_array(dims, new_value)
      res = BASICArray.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ZER1%
class FunctionZer1I < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = IntegerValue.new(0)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.make_array(dims, new_value)
      res = BASICArray.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ZER1$
class FunctionZer1T < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = TextValue.new('')

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = BASICArray.make_array(dims, new_value)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.make_array(dims, new_value)
      res = BASICArray.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ZER, ZER2
class FunctionZer2 < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = NumericValue.new(0)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.make_array(dims, new_value) if dims.size == 1
      values = Matrix.make_matrix(dims, new_value) if dims.size == 2
      res = Matrix.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ZER2%
class FunctionZer2I < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = IntegerValue.new(0)

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.make_array(dims, new_value) if dims.size == 1
      values = Matrix.make_matrix(dims, new_value) if dims.size == 2
      res = Matrix.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ZER2$
class FunctionZer2T < AbstractFunction
  def initialize(text)
    super

    @shape = :matrix

    @default_shape = :scalar
    @signature0 = []
    @signature1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    if !type_stack.empty? && (type_stack[-1].class.to_s == 'Array')
      @arg_types = type_stack.pop
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    if !shape_stack.empty? && (shape_stack[-1].class.to_s == 'Array')
      @arg_shapes = shape_stack.pop
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    if !constant_stack.empty? && (constant_stack[-1].class.to_s == 'Array')
      constants = constant_stack.pop

      if constants.empty?
        @constant = false
      else
        @constant = true
        constants.each { |c| @constant &&= c }
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    new_value = TextValue.new('')

    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature1)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature2)
        dims = args.clone
        values = Matrix.make_array(dims, new_value) if dims.size == 1
        values = Matrix.make_matrix(dims, new_value) if dims.size == 2
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.make_array(dims, new_value) if dims.size == 1
      values = Matrix.make_matrix(dims, new_value) if dims.size == 2
      res = Matrix.new(dims, values)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# class to make functions, given the name
class FunctionFactory
  @functions = {
    'ABS' => FunctionAbs,
    'ASC' => FunctionAscii,
    'ASC%' => FunctionAscii,
    'ASCII' => FunctionAscii,
    'ASCII%' => FunctionAscii,
    'ARCCOS' => FunctionArcCos,
    'ARCSIN' => FunctionArcSin,
    'ARCTAN' => FunctionArcTan,
    'ATN' => FunctionArcTan,
    'AVG' => FunctionAvg,
    'CHR$' => FunctionChr,
    'CON' => FunctionCon2,
    'CON1' => FunctionCon1,
    'CON1%' => FunctionCon1I,
    'CON1$' => FunctionCon1T,
    'CON2' => FunctionCon2,
    'CON2%' => FunctionCon2I,
    'CON2$' => FunctionCon2T,
    'COS' => FunctionCos,
    'COT' => FunctionCot,
    'CSC' => FunctionCsc,
    'DEG' => FunctionDeg,
    'DET' => FunctionDet,
    'ERL' => FunctionErl,
    'ERR' => FunctionErr,
    'EXP' => FunctionExp,
    'FIX' => FunctionFix,
    'FIX%' => FunctionFix,
    'FRAC' => FunctionFrac,
    'IDN' => FunctionIdn,
    'INSTR' => FunctionInstr,
    'INSTR%' => FunctionInstr,
    'INT' => FunctionInt,
    'INT%' => FunctionInt,
    'INV' => FunctionInv,
    'LEFT$' => FunctionLeft,
    'LEN' => FunctionLen,
    'LOG' => FunctionLog,
    'LOWER$' => FunctionLowerT,
    'MAXA' => FunctionMaxA,
    'MAXA%' => FunctionMaxAI,
    'MAXA$' => FunctionMaxAT,
    'MAXM' => FunctionMaxM,
    'MAXM%' => FunctionMaxMI,
    'MAXM$' => FunctionMaxMT,
    'MEDIAN' => FunctionMedian,
    'MEDIAN%' => FunctionMedianIT,
    'MEDIAN$' => FunctionMedianIT,
    'MID$' => FunctionMid,
    'MINA' => FunctionMinA,
    'MINA%' => FunctionMinAI,
    'MINA$' => FunctionMinAT,
    'MINM' => FunctionMinM,
    'MINM%' => FunctionMinMI,
    'MINM$' => FunctionMinMT,
    'MOD' => FunctionMod,
    'NCOL' => FunctionNcol,
    'NCOL%' => FunctionNcol,
    'NELEM' => FunctionNelem,
    'NELEM%' => FunctionNelem,
    'NROW' => FunctionNrow,
    'NROW%' => FunctionNrow,
    'NUM' => FunctionNum,
    'NUM$' => FunctionStr,
    'PACK$' => FunctionPack,
    'PROD' => FunctionProd,
    'PROD%' => FunctionProd,
    'RAD' => FunctionRad,
    'RIGHT$' => FunctionRight,
    'RND' => FunctionRnd,
    'RND%' => FunctionRndI,
    'RND$' => FunctionRndT,
    'RND1' => FunctionRnd1,
    'RND1%' => FunctionRnd1I,
    'RND1$' => FunctionRnd1T,
    'RND2' => FunctionRnd2,
    'RND2%' => FunctionRnd2I,
    'RND2$' => FunctionRnd2T,
    'REV1' => FunctionRev1,
    'REV1%' => FunctionRev1,
    'REV1$' => FunctionRev1,
    'ROUND' => FunctionRound,
    'SEC' => FunctionSec,
    'SGN' => FunctionSgn,
    'SGN%' => FunctionSgn,
    'SIN' => FunctionSin,
    'SORT1' => FunctionSort1,
    'SORT1%' => FunctionSort1,
    'SORT1$' => FunctionSort1,
    'SORT2' => FunctionSort2,
    'SORT2%' => FunctionSort2,
    'SORT2$' => FunctionSort2,
    'SPACE$' => FunctionSpace,
    'SPC$' => FunctionSpace,
    'SPLIT1$' => FunctionSplit1T,
    'SQR' => FunctionSqr,
    'STR$' => FunctionStr,
    'STRING$' => FunctionString,
    'SUM' => FunctionSum,
    'SUM%' => FunctionSum,
    'TAB' => FunctionTab,
    'TAN' => FunctionTan,
    'TIME' => FunctionTime,
    'TRN' => FunctionTrn,
    'UNIQ1' => FunctionUniq1,
    'UNIQ1%' => FunctionUniq1,
    'UNIQ1$' => FunctionUniq1,
    'UNPACK' => FunctionUnpack,
    'UNPACK%' => FunctionUnpack,
    'UPPER$' => FunctionUpperT,
    'VAL' => FunctionVal,
    'ZER' => FunctionZer2,
    'ZER1' => FunctionZer1,
    'ZER1%' => FunctionZer1I,
    'ZER1$' => FunctionZer1T,
    'ZER2' => FunctionZer2,
    'ZER2%' => FunctionZer2I,
    'ZER2$' => FunctionZer2T
  }

  def self.valid?(text)
    @functions.key?(text)
  end

  def self.make(text)
    @functions[text].new(text) if @functions.key?(text)
  end

  def self.function_names
    @functions.keys
  end

  def self.user_function_names
    fns_n = ('FNA'..'FNZ').to_a
    fns_n_n = ('FNA0'..'FNZ9').to_a
    fns_s = ('FNA$'..'FNZ$').to_a
    fns_n_s = ('FNA0$'..'FNZ9$').to_a
    fns_i = ('FNA%'..'FNZ%').to_a
    fns_n_i = ('FNA0%'..'FNZ9%').to_a
    fns_n + fns_n_n + fns_s + fns_n_s + fns_i + fns_n_i
  end
end
