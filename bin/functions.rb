# function (provides a result)
class AbstractFunction < AbstractElement
  attr_reader :name
  attr_reader :content_type

  def initialize(text)
    super()

    @name = text
    @function = true
    @content_type = :numeric
    @content_type = :string if @name.to_s[-1] == '$'
    @content_type = :integer if @name.to_s[-1] == '%'
    @valref = :value
    @operand = true
    @precedence = 7
  end

  def dump
    self.class.to_s
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

    shape = spec['shape']
    shape_compatible = match_arg_shape(value, shape)

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
end

# Function that expects scalar parameters
class AbstractScalarFunction < AbstractFunction
  def initialize(text)
    super
  end

  def default_shape
    :scalar
  end
end

# Function that expects array parameters
class AbstractArrayFunction < AbstractFunction
  def initialize(text)
    super
  end

  def default_shape
    :array
  end
end

# Function that expects matrix parameters
class AbstractMatrixFunction < AbstractFunction
  def initialize(text)
    super
  end

  def default_shape
    :matrix
  end

  def check_square(dims)
    raise(BASICSyntaxError, @name + ' requires matrix') unless dims.size == 2
    raise BASICRuntimeError.new(:te_mat_no_sq, @name) unless dims[1] == dims[0]
  end
end

# User-defined function (provides a scalar value)
class UserFunction < AbstractScalarFunction
  attr_writer :valref

  def self.accept?(token)
    classes = %w[UserFunctionToken]
    classes.include?(token.class.to_s)
  end

  def initialize(text)
    super
    @user_function = true
    @shape = :scalar
  end

  def to_s
    @name.to_s
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

  def evaluate(interpreter, stack)
    x = false
    x = evaluate_value(interpreter, stack) if @valref == :value
    x = evaluate_ref(interpreter, stack) if @valref == :reference
    x
  end

  private

  # return a single value
  def evaluate_value(interpreter, stack)
    arguments = stack.pop
    signature = XrefEntry.make_signature(arguments)
    definition = interpreter.get_user_function(@name, signature)

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
    rescue BASICRuntimeException => e
      interpreter.clear_user_var_values
      raise e
    end

    interpreter.clear_user_var_values
    results[0]
  end

  def evaluate_ref(interpreter, stack)
    x = nil
    x = evaluate_ref_scalar(interpreter, stack) if @shape == :scalar

    x = evaluate_ref_compound(interpreter, stack) if
      @shape == :array || @shape == :matrix
    x
  end

  # return a single value, a reference to this object
  def evaluate_ref_scalar(interpreter, stack)
    if previous_is_array(stack)
      subscripts = stack.pop
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
  def evaluate_ref_compound(interpreter, stack)
    if previous_is_array(stack)
      subscripts = stack.pop
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
class FunctionAbs < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].abs
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function ASC
class FunctionAsc < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(interpreter, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      text = args[0].to_v

      raise BASICRuntimeError.new(:te_str_empty, @name) if text.empty?

      value = text[0].ord

      raise BASICRuntimeError.new(:te_val_out, @name) unless
        value.between?(32, 126) || interpreter.asc_allow_all

      token = NumericConstantToken.new(value.to_s)
      NumericConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function ARCCOS
class FunctionArcCos < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature)

    args[0].arccos
  end
end

# function ARCSIN
class FunctionArcSin < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature)

    args[0].arcsin
  end
end

# function ARCTAN
class FunctionArcTan < AbstractScalarFunction
  def initialize(text)
    super

    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, stack)
    args = stack.pop

    if match_args_to_signature(args, @signature_1)
      args[0].atn
    elsif match_args_to_signature(args, @signature_2)
      args[0].atn2(args[1])
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function CHR$
class FunctionChr < AbstractScalarFunction
  def initialize(text)
    super

    @content_type = :string
    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(interpreter, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      value = args[0].to_i

      raise BASICRuntimeError.new(:te_val_out, @name) unless
        value.between?(32, 126) || interpreter.chr_allow_all

      text = value.chr
      quoted = '"' + text + '"'
      token = TextConstantToken.new(quoted)
      TextConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function CON1
class FunctionCon1 < AbstractScalarFunction
  def initialize(text)
    super

    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(interpreter, stack)
    if previous_is_array(stack)
      args = stack.pop

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.one_values(dims)
        BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = args.clone
        values = BASICArray.one_values(dims)
        BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.one_values(dims)
      BASICArray.new(dims, values)
    end
  end
end

# function CON, CON2
class FunctionCon2 < AbstractScalarFunction
  def initialize(text)
    super

    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def evaluate(interpreter, stack)
    if previous_is_array(stack)
      args = stack.pop

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.one_values(dims)
        Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = args.clone
        values = Matrix.one_values(dims)
        Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_2)
        dims = args.clone
        values = Matrix.one_values(dims)
        Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.one_values(dims)
      Matrix.new(dims, values)
    end
  end
end

# function COS
class FunctionCos < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].cos
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function COT
class FunctionCot < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].cot
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function CSC
class FunctionCsc < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature)

    args[0].csc
  end
end

# function DET
class FunctionDet < AbstractMatrixFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].determinant
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function ERL
class FunctionErl < AbstractScalarFunction
  def initialize(text)
    super

    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(interpreter, stack)
    if previous_is_array(stack)
      args = stack.pop

      if match_args_to_signature(args, @signature_0)
        arg = NumericConstant.new(0)
        interpreter.error_line(arg)
      elsif match_args_to_signature(args, @signature_1)
        interpreter.error_line(args[0])
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      arg = NumericConstant.new(0)
      interpreter.error_line(arg)
    end
  end
end

# function EXP
class FunctionExp < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].exp
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function FRAC
class FunctionFrac < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(_, stack)
    args = stack.pop

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature)

    args[0] - args[0].truncate
  end
end

# function IDN
class FunctionIdn < AbstractScalarFunction
  def initialize(text)
    super

    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def evaluate(interpreter, stack)
    if previous_is_array(stack)
      args = stack.pop

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.one_values(dims)
        Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = [args[0]] * 2
        values = Matrix.identity_values(dims)
        Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_2)
        raise BASICRuntimeError.new(:te_mat_no_sq, @name) unless
          args[1] == args[0]

        dims = args.clone
        values = Matrix.identity_values(dims)
        Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      raise BASICRuntimeError.new(:te_mat_no_sq, @name) unless
        args.size == 2 && args[1] == args[0]

      dims = args.clone
      values = Matrix.identity_values(dims)
      Matrix.new(dims, values)
    end
  end
end

# function INSTR$
class FunctionInstr < AbstractScalarFunction
  def initialize(text)
    super

    @content_type = :string

    @signature = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :string, 'shape' => :scalar }
    ]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
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
      IntegerConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function INT
class FunctionInt < AbstractScalarFunction
  def initialize(text)
    super

    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 = [{ 'type' => :boolean, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(interpreter, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature_1)
      interpreter.int_floor? ? args[0].floor : args[0].truncate
    elsif match_args_to_signature(args, @signature_2)
      interpreter.int_floor? ? args[0].to_numeric.floor : args[0].to_numeric.truncate
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function INV
class FunctionInv < AbstractMatrixFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      dims = args[0].dimensions
      check_square(dims)
      Matrix.new(dims.clone, args[0].inverse_values)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function LEFT$
class FunctionLeft < AbstractScalarFunction
  def initialize(text)
    super

    @content_type = :string

    @signature = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
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
      TextConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function LEN
class FunctionLen < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      text = args[0].to_v
      length = text.size
      token = NumericConstantToken.new(length.to_s)
      NumericConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function LOG
class FunctionLog < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].log
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function MID$
class FunctionMid < AbstractScalarFunction
  def initialize(text)
    super

    @content_type = :string

    @signature = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
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
      TextConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function MOD
class FunctionMod < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  # return a single value
  def evaluate(_, stack)
    args = stack.pop

    raise BASICRuntimeError(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature)

    args[0].mod(args[1])
  end
end

# function PACK
class FunctionPack < AbstractArrayFunction
  def initialize(text)
    super

    @content_type = :string
    @signature = [{ 'type' => :numeric, 'shape' => :array }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      array = args[0]
      dims = array.dimensions

      raise(BASICSyntaxError, @name + ' requires array') unless dims.size == 1

      array.pack
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function RIGHT$
class FunctionRight < AbstractScalarFunction
  def initialize(text)
    super

    @content_type = :string

    @signature = [
      { 'type' => :string, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      value = args[0].to_v
      count = args[1].to_i

      raise BASICRuntimeError.new(:te_count_inv, @name) if count < 0
      
      start = value.size - count
      start = 0 if start < 0
      text = value[start..-1]
      quoted = '"' + text + '"'
      token = TextConstantToken.new(quoted)
      TextConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function ROUND
class FunctionRound < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  def evaluate(_, stack)
    args = stack.pop

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature)

    args[0].round(args[1])
  end
end

# function RND
class FunctionRnd < AbstractScalarFunction
  def initialize(text)
    super

    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  # return a single value
  def evaluate(interpreter, stack)
    if previous_is_array(stack)
      args = stack.pop

      if match_args_to_signature(args, @signature_0)
        arg = default_args(interpreter)
        interpreter.rand(arg)
      elsif match_args_to_signature(args, @signature_1)
        interpreter.rand(args[0])
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      arg = default_args(interpreter)
      interpreter.rand(arg)
    end
  end
end

# function SEC
class FunctionSec < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop

    raise BASICRuntimeError.new(:te_args_no_match, @name) unless
      match_args_to_signature(args, @signature)

    args[0].sec
  end
end

# function SGN
class FunctionSgn < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].sign
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function SIN
class FunctionSin < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].sin
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function SPC$
class FunctionSpc < AbstractScalarFunction
  def initialize(text)
    super

    @content_type = :string
    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop

    if match_args_to_signature(args, @signature)
      width = args[0].to_v

      if width > 0
        spaces = ' ' * width
      else
        # zero or negative value yields empty string
        spaces = ''
      end

      quoted = '"' + spaces + '"'
      v = TextConstantToken.new(quoted)
      TextConstant.new(v)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function SQR
class FunctionSqr < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].sqrt
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function STR$
class FunctionStr < AbstractScalarFunction
  def initialize(text)
    super

    @content_type = :string
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 = [
      { 'type' => :numeric, 'shape' => :scalar },
      { 'type' => :numeric, 'shape' => :scalar }
    ]
  end

  # return a single value
  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature_1)
      text = args[0].to_s
      quoted = '"' + text + '"'
      token = TextConstantToken.new(quoted)
      TextConstant.new(token)
    elsif match_args_to_signature(args, @signature_2)
      places = args[1].to_i
      value = args[0].to_f
      text = sprintf('%.*f', places, value)
      quoted = '"' + text + '"'
      token = TextConstantToken.new(quoted)
      TextConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function TAB
class FunctionTab < AbstractScalarFunction
  def initialize(text)
    super

    @content_type = :string
    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(interpreter, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
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
      TextConstant.new(v)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function TAN
class FunctionTan < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      args[0].tan
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function TIME
class FunctionTime < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(interpreter, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      # ignore argument
      now = Time.now
      start = interpreter.start_time
      result = now - start
      NumericConstant.new(result)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function UNPACK
class FunctionUnpack < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      text = args[0]
      text.unpack
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function TRN
class FunctionTrn < AbstractMatrixFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :numeric, 'shape' => :matrix }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      dims = args[0].dimensions
      new_dims = [dims[1], dims[0]]
      Matrix.new(new_dims, args[0].transpose_values)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function VAL
class FunctionVal < AbstractScalarFunction
  def initialize(text)
    super

    @signature = [{ 'type' => :string, 'shape' => :scalar }]
  end

  def evaluate(_, stack)
    args = stack.pop
    if match_args_to_signature(args, @signature)
      f = args[0].to_v.to_f
      token = NumericConstantToken.new(f)
      NumericConstant.new(token)
    else
      raise BASICRuntimeError.new(:te_args_no_match, @name)
    end
  end
end

# function ZER1
class FunctionZer1 < AbstractScalarFunction
  def initialize(text)
    super

    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
  end

  def evaluate(interpreter, stack)
    if previous_is_array(stack)
      args = stack.pop

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = BASICArray.zero_values(dims)
        BASICArray.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = args.clone
        values = BASICArray.zero_values(dims)
        BASICArray.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = BASICArray.zero_values(dims)
      BASICArray.new(dims, values)
    end
  end
end

# function ZER, ZER2
class FunctionZer2 < AbstractScalarFunction
  def initialize(text)
    super

    @signature_0 = []
    @signature_1 = [{ 'type' => :numeric, 'shape' => :scalar }]
    @signature_2 =
      [
        { 'type' => :numeric, 'shape' => :scalar },
        { 'type' => :numeric, 'shape' => :scalar }
      ]
  end

  def evaluate(interpreter, stack)
    if previous_is_array(stack)
      args = stack.pop

      if match_args_to_signature(args, @signature_0)
        args = default_args(interpreter)
        dims = args.clone
        values = Matrix.zero_values(dims)
        Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_1)
        dims = args.clone
        values = Matrix.zero_values(dims)
        Matrix.new(dims, values)
      elsif match_args_to_signature(args, @signature_2)
        dims = args.clone
        values = Matrix.zero_values(dims)
        Matrix.new(dims, values)
      else
        raise BASICRuntimeError.new(:te_args_no_match, @name)
      end
    else
      args = default_args(interpreter)
      dims = args.clone
      values = Matrix.zero_values(dims)
      Matrix.new(dims, values)
    end
  end
end

# class to make functions, given the name
class FunctionFactory
  @functions = {
    'ABS' => FunctionAbs,
    'ASC' => FunctionAsc,
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
    'EXP' => FunctionExp,
    'FRAC' => FunctionFrac,
    'IDN' => FunctionIdn,
    'INSTR$' => FunctionInstr,
    'INT' => FunctionInt,
    'INV' => FunctionInv,
    'LEFT$' => FunctionLeft,
    'LEN' => FunctionLen,
    'LOG' => FunctionLog,
    'MID$' => FunctionMid,
    'MOD' => FunctionMod,
    'NUM$' => FunctionStr,
    'PACK$' => FunctionPack,
    'RIGHT$' => FunctionRight,
    'RND' => FunctionRnd,
    'ROUND' => FunctionRound,
    'SEC' => FunctionSec,
    'SGN' => FunctionSgn,
    'SIN' => FunctionSin,
    'SPC$' => FunctionSpc,
    'SQR' => FunctionSqr,
    'STR$' => FunctionStr,
    'TAB' => FunctionTab,
    'TAN' => FunctionTan,
    'TIME' => FunctionTime,
    'TRN' => FunctionTrn,
    'UNPACK' => FunctionUnpack,
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
    functions_numeric = ('FNA'..'FNZ').to_a
    functions_string = ('FNA$'..'FNZ$').to_a
    functions_integer = ('FNA%'..'FNZ%').to_a
    functions_numeric + functions_string + functions_integer
  end
end
