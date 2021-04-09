# function (provides a result)
class AbstractFunction < AbstractElement
  attr_reader :name
  attr_reader :default_shape
  attr_reader :content_type
  attr_reader :shape
  attr_reader :constant

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
    make_signature(@arg_types, @arg_shapes)
  end

  def pop_stack(stack)
    stack.pop
  end

  def dump
    result = make_type_sigil(@content_type) + make_shape_sigil(@shape)
    const = @constant ? '=' : ''
    "#{self.class}:#{@name}#{signature} -> #{const}#{result}"
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
    raise(BASICSyntaxError, @name + ' requires matrix') unless dims.size == 2

    raise BASICRuntimeError.new(:te_mat_no_sq, @name) unless
      dims[1] == dims[0]
  end
end

# User-defined function (provides a scalar value)
class UserFunction < AbstractFunction
  attr_writer :valref
  attr_writer :set_dims

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

  def to_s
    @name.to_s
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      @arg_types = type_stack.pop if
        type_stack[-1].class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      @arg_shapes = shape_stack.pop if shape_stack[-1].class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      constant_stack.pop if constant_stack[-1].class.to_s == 'Array'
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
    definition = interpreter.get_user_function(@name, sigils)

    # dummy variable names and their (now known) values
    params = definition.arguments
    param_names_values = params.zip(arguments)
    names_and_values = Hash[param_names_values]
    interpreter.define_user_var_values(names_and_values)

    begin
      expression = definition.expression
      if !expression.nil?
        results = expression.evaluate(interpreter)
      else
        interpreter.run_user_function(@name)

        results = [interpreter.get_value(@name)]
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
  def evaluate_ref_scalar(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      subscripts = arg_stack.pop
      @subscripts = interpreter.normalize_subscripts(subscripts)
      num_args = @subscripts.length

      if num_args.zero?
        raise(BASICSyntaxError,
              'Variable expects subscripts, found empty parentheses')
      end

      interpreter.check_subscripts(@variable_name, @subscripts)
    end
    self
  end

  # return a single value, a reference to this object
  def evaluate_ref_compound(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      subscripts = arg_stack.pop
      @subscripts = interpreter.normalize_subscripts(subscripts)
      num_args = @subscripts.length

      if num_args.zero?
        raise(BASICSyntaxError,
              'Variable expects subscripts, found empty parentheses')
      end

      interpreter.check_subscripts(@variable_name, @subscripts)
    end

    self
  end
end

# function ABS
class FunctionAbs < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].abs

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ASCII, ASC
class FunctionAscii < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    text = args[0].to_v

    raise BASICRuntimeError.new(:te_str_empty, @name) if text.empty?

    value = text[0].ord

    raise BASICRuntimeError.new(:te_val_out, @name) unless
      value.between?(32, 126) || $options['asc_allow_all'].value

    res = NumericConstant.new(value)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function ASCII%
class FunctionAsciiI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    text = args[0].to_v

    raise BASICRuntimeError.new(:te_str_empty, @name) if text.empty?

    value = text[0].ord

    raise BASICRuntimeError.new(:te_val_out, @name) unless
      value.between?(32, 126) || $options['asc_allow_all'].value

    res = IntegerConstant.new(value)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature_1)
      res = args[0].atn
    elsif match_args_to_signature(args, @signature_2)
      res = args[0].atn2(args[1])
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    value = args[0].to_i

    raise BASICRuntimeError.new(:te_val_out, @name) unless
      value.between?(32, 126) || $options['chr_allow_all'].value

    text = value.chr
    quoted = '"' + text + '"'
    token = TextConstantToken.new(quoted)
    res = TextConstant.new(token)

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
    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      @arg_types = type_stack.pop if
        type_stack[-1].class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      @arg_shapes = shape_stack.pop if shape_stack[-1].class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      if constant_stack[-1].class.to_s == 'Array'
        constants = constant_stack.pop

        if constants.empty?
          @constant = false
        else
          @constant = true
          constants.each { |c| @constant &&= c }
        end
      end
    end

    constant_stack.push(@constant)
  end
  
  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.one_values(dims)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = args.clone
        values = BASICArray.one_values(dims)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.one_values(dims)
      res = BASICArray.new(dims, values)
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
    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      @arg_types = type_stack.pop if
        type_stack[-1].class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      @arg_shapes = shape_stack.pop if shape_stack[-1].class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      if constant_stack[-1].class.to_s == 'Array'
        constants = constant_stack.pop

        if constants.empty?
          @constant = false
        else
          @constant = true
          constants.each { |c| @constant &&= c }
        end
      end
    end

    constant_stack.push(@constant)
  end
  
  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.one_values(dims)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = args.clone
        values = Matrix.one_values(dims)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_2)
        dims = args.clone
        values = Matrix.one_values(dims)
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.one_values(dims)
      res = Matrix.new(dims, values)
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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].csc

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

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
    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      @arg_types = type_stack.pop if
        type_stack[-1].class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      @arg_shapes = shape_stack.pop if shape_stack[-1].class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      constant_stack.pop if constant_stack[-1].class.to_s == 'Array'
    end

    # ERL() is never constant
    
    constant_stack.push(@constant)
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature_0)
        arg = NumericConstant.new(0)
        res = interpreter.error_line(arg)
      elsif match_args_to_signature(args, @signature_1)
        res = interpreter.error_line(args[0])
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      arg = NumericConstant.new(0)
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
    @signature_0 = []
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      @arg_types = type_stack.pop if
        type_stack[-1].class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      @arg_shapes = shape_stack.pop if shape_stack[-1].class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      constant_stack.pop if constant_stack[-1].class.to_s == 'Array'
    end

    # ERR() is never constant
    
    constant_stack.push(@constant)
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature_0)
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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].exp

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function FIX
class FunctionFix < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].floor

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function FIX%
class FunctionFixI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].floor.to_int

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0] - args[0].truncate

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
    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      @arg_types = type_stack.pop if
        type_stack[-1].class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      @arg_shapes = shape_stack.pop if shape_stack[-1].class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      if constant_stack[-1].class.to_s == 'Array'
        constants = constant_stack.pop

        if constants.empty?
          @constant = false
        else
          @constant = true
          constants.each { |c| @constant &&= c }
        end
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.identity_values(dims)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = [args[0]] * 2
        values = Matrix.identity_values(dims)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_2)
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

# function INSTR
class FunctionInstr < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_3 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_3)

    start = args[0].to_i

    raise BASICRuntimeError.new(:te_val_out, @name) if start < 1

    start -= 1
    value = args[1].to_v
    search = args[2].to_v
    index = value.index(search, start)

    if index.nil?
      index = 0
    else
      index += 1
    end

    token = IntegerConstantToken.new(index)
    res = IntegerConstant.new(token)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function INT
class FunctionInt < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 = [{ 'type' => :boolean, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature_1)
      res = $options['int_floor'].value ? args[0].floor : args[0].truncate
    elsif match_args_to_signature(args, @signature_2)
      res = $options['int_floor'].value ? args[0].to_numeric.floor : args[0].to_numeric.truncate
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function INT%
class FunctionIntI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    x = $options['int_floor'].value ? args[0].floor : args[0].truncate
    res = x.to_int

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

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
    @signature_2 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_2)

    value = args[0].to_v
    count = args[1].to_i

    raise BASICRuntimeError.new(:te_count_inv, @name) if count < 0

    if count > 0
      count2 = count - 1
      text = value[0..count2]
    else
      text = ''
    end

    quoted = '"' + text + '"'
    token = TextConstantToken.new(quoted)
    res = TextConstant.new(token)

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
    @signature_1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    text = args[0].to_v
    length = text.size
    token = NumericConstantToken.new(length.to_s)
    res = NumericConstant.new(token)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].log

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function LOG10
class FunctionLog10 < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].log10

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function LOG2
class FunctionLog2 < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].log2

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
    @signature_3 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_3)

    value = args[0].to_v
    start = args[1].to_i
    length = args[2].to_i

    raise BASICRuntimeError.new(:te_count_inv, @name) if start < 1

    raise BASICRuntimeError.new(:te_len_inv, @name) if length < 0

    if length > 0
      start_index = start - 1
      end_index = start_index + length - 1

      text = value[start_index..end_index]
      text = '' if text.nil?
    else
      text = ''
    end

    quoted = '"' + text + '"'
    token = TextConstantToken.new(quoted)
    res = TextConstant.new(token)

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
    @signature_2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  # return a single value
  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_2)

    res = args[0].mod(args[1])

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function NELEM
class FunctionNelem < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature_1 = [{ 'type' => :numeric, 'shape' => :array }]
    @signature_2 = [{ 'type' => :integer, 'shape' => :array }]
    @signature_3 = [{ 'type' => :string, 'shape' => :array }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1) ||
      match_args_to_signature(args, @signature_2) ||
      match_args_to_signature(args, @signature_3)

    res = args[0].size

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function NELEM%
class FunctionNelemI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature_1 = [{ 'type' => :numeric, 'shape' => :array }]
    @signature_2 = [{ 'type' => :integer, 'shape' => :array }]
    @signature_3 = [{ 'type' => :string, 'shape' => :array }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1) ||
      match_args_to_signature(args, @signature_2) ||
      match_args_to_signature(args, @signature_3)

    res = args[0].size.to_int

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

  def evaluate(_, arg_stack)
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

    token = NumericConstantToken.new(f)
    res = NumericConstant.new(token)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    array = args[0]
    dims = array.dimensions

    raise(BASICSyntaxError, @name + ' requires array') unless dims.size == 1

    res = array.pack

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
    @signature_2 = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_2)

    value = args[0].to_v
    count = args[1].to_i

    raise BASICRuntimeError.new(:te_count_inv, @name) if count < 0

    start = value.size - count
    start = 0 if start < 0
    text = value[start..-1]
    quoted = '"' + text + '"'
    token = TextConstantToken.new(quoted)
    res = TextConstant.new(token)

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
    @signature_2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_2)

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
    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      @arg_types = type_stack.pop if
        type_stack[-1].class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      @arg_shapes = shape_stack.pop if shape_stack[-1].class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      constant_stack.pop if constant_stack[-1].class.to_s == 'Array'
    end

    # RND() is never constant
    
    constant_stack.push(@constant)
  end

  # return a single value
  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature_0)
        arg = default_args(interpreter)
        res = interpreter.rand(arg)
      elsif match_args_to_signature(args, @signature_1)
        res = interpreter.rand(args[0])
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      arg = default_args(interpreter)
      res = interpreter.rand(arg)
    end

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].sec

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SGN
class FunctionSgn < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].sign

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SGN%
class FunctionSgnI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :integer, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    res = args[0].sin

    @cached = res if @constant && $options['cache_const_expr']
    res

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    width = args[0].to_v

    if width > 0
      spaces = ' ' * width
    else
      # zero or negative value yields empty string
      spaces = ''
    end

    quoted = '"' + spaces + '"'
    v = TextConstantToken.new(quoted)
    res = TextConstant.new(v)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  # return a single value
  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    if match_args_to_signature(args, @signature_1)
      text = args[0].to_s
      quoted = '"' + text + '"'
      token = TextConstantToken.new(quoted)
      res = TextConstant.new(token)
    elsif match_args_to_signature(args, @signature_2)
      places = args[1].to_i
      value = args[0].to_f
      text = sprintf('%.*f', places, value)
      quoted = '"' + text + '"'
      token = TextConstantToken.new(quoted)
      res = TextConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SUM
class FunctionSum < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature_1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    sum = args[0].sum
    res = NumericConstant.new(sum)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function SUM%
class FunctionSumI < AbstractFunction
  def initialize(text)
    super

    @shape = :scalar

    @default_shape = :array
    @signature_1 = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    sum = args[0].sum
    res = IntegerConstant.new(sum)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      constant_stack.pop if constant_stack[-1].class.to_s == 'Array'
    end

    # TAB() is never constant
    
    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    console_io = interpreter.console_io
    width = console_io.columns_to_advance(args[0].to_v)

    if width > 0
      spaces = ' ' * width
    elsif width < 0
      spaces = "\b" * -width
    else
      spaces = ''
    end

    quoted = '"' + spaces + '"'
    v = TextConstantToken.new(quoted)
    res = TextConstant.new(v)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(interpreter, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    # ignore argument
    now = Time.now
    start = interpreter.start_time
    result = now - start
    res = NumericConstant.new(result)

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function UNPACK
class FunctionUnpack < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    text = args[0]
    res = text.na_unpack

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

# function UNPACK%
class FunctionUnpackI < AbstractFunction
  def initialize(text)
    super

    @shape = :array

    @default_shape = :scalar
    @signature_1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    text = args[0]
    res = text.ia_unpack

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
    @signature_1 = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    dims = args[0].dimensions
    new_dims = [dims[1], dims[0]]
    res = Matrix.new(new_dims, args[0].transpose_values)

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
    @signature_1 = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_, arg_stack)
    args = arg_stack.pop

    return @cached unless @cached.nil?

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature_1)

    f = args[0].to_v.to_f
    token = NumericConstantToken.new(f)
    res = NumericConstant.new(token)

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
    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      @arg_types = type_stack.pop if
        type_stack[-1].class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      @arg_shapes = shape_stack.pop if shape_stack[-1].class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      if constant_stack[-1].class.to_s == 'Array'
        constants = constant_stack.pop

        if constants.empty?
          @constant = false
        else
          @constant = true
          constants.each { |c| @constant &&= c }
        end
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.zero_values(dims)
        res = BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = args.clone
        values = BASICArray.zero_values(dims)
        res = BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.zero_values(dims)
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
    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def set_content_type(type_stack)
    unless type_stack.empty?
      @arg_types = type_stack.pop if
        type_stack[-1].class.to_s == 'Array'
    end

    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    unless shape_stack.empty?
      @arg_shapes = shape_stack.pop if shape_stack[-1].class.to_s == 'Array'
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    unless constant_stack.empty?
      if constant_stack[-1].class.to_s == 'Array'
        constants = constant_stack.pop

        if constants.empty?
          @constant = false
        else
          @constant = true
          constants.each { |c| @constant &&= c }
        end
      end
    end

    constant_stack.push(@constant)
  end

  def evaluate(interpreter, arg_stack)
    if previous_is_array(arg_stack)
      args = arg_stack.pop

      return @cached unless @cached.nil?

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.zero_values(dims)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = args.clone
        values = Matrix.zero_values(dims)
        res = Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_2)
        dims = args.clone
        values = Matrix.zero_values(dims)
        res = Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.zero_values(dims)
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
    'ASC%' => FunctionAsciiI,
    'ASCII' => FunctionAscii,
    'ASCII%' => FunctionAsciiI,
    'ARCCOS' => FunctionArcCos,
    'ARCSIN' => FunctionArcSin,
    'ARCTAN' => FunctionArcTan,
    'ATN' => FunctionArcTan,
    'CHR$' => FunctionChr,
    'CON' => FunctionCon2,
    'CON1' => FunctionCon1,
    'CON2' => FunctionCon2,
    'COS' => FunctionCos,
    'COT' => FunctionCot,
    'CSC' => FunctionCsc,
    'DET' => FunctionDet,
    'ERL' => FunctionErl,
    'ERR' => FunctionErr,
    'EXP' => FunctionExp,
    'FIX' => FunctionFix,
    'FIX%' => FunctionFixI,
    'FRAC' => FunctionFrac,
    'IDN' => FunctionIdn,
    'INSTR' => FunctionInstr,
    'INT' => FunctionInt,
    'INT%' => FunctionIntI,
    'INV' => FunctionInv,
    'LEFT$' => FunctionLeft,
    'LEN' => FunctionLen,
    'LOG' => FunctionLog,
    'LOG10' => FunctionLog10,
    'LOG2' => FunctionLog2,
    'MID$' => FunctionMid,
    'MOD' => FunctionMod,
    'NELEM' => FunctionNelem,
    'NELEM%' => FunctionNelemI,
    'NUM' => FunctionNum,
    'NUM$' => FunctionStr,
    'PACK$' => FunctionPack,
    'RIGHT$' => FunctionRight,
    'RND' => FunctionRnd,
    'ROUND' => FunctionRound,
    'SEC' => FunctionSec,
    'SGN' => FunctionSgn,
    'SGN%' => FunctionSgnI,
    'SIN' => FunctionSin,
    'SPACE$' => FunctionSpace,
    'SPC$' => FunctionSpace,
    'SQR' => FunctionSqr,
    'STR$' => FunctionStr,
    'SUM' => FunctionSum,
    'SUM%' => FunctionSumI,
    'TAB' => FunctionTab,
    'TAN' => FunctionTan,
    'TIME' => FunctionTime,
    'TRN' => FunctionTrn,
    'UNPACK' => FunctionUnpack,
    'UNPACK%' => FunctionUnpackI,
    'VAL' => FunctionVal,
    'ZER' => FunctionZer2,
    'ZER1' => FunctionZer1,
    'ZER2' => FunctionZer2
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
