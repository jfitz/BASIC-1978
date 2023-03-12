# frozen_string_literal: true

# operators
class Operator < AbstractElement
  attr_reader :content_type, :shape, :warnings, :arguments, :precedence

  def initialize(text)
    super()

    @op = text.to_s
    @operation = nil
    @content_type = :unknown
    @shape = :unknown
    @constant = false
    @warnings = []
    @arguments = nil
    @precedence = 0
    @operator = true
    @arg_types = nil
    @arg_shapes = []
    @arg_consts = []
  end

  def sigils
    Sigils.make_sigils_2(@arg_types, @arg_shapes)
  end

  def signature
    make_signature(@arg_types, @arg_shapes)
  end

  def dump
    result = Sigils.make_type_sigil(@content_type) + Sigils.make_shape_sigil(@shape)
    const = @constant ? '=' : ''
    "#{self.class}:#{@op}#{signature} -> #{const}#{result}"
  end

  def constant?
    @constant
  end

  def pound?
    false
  end

  def to_s
    @op
  end

  # evaluate() in each subclass
end

# Unary scalar operators
class UnaryOperator < Operator
  @operators = ['+', '-', '#', ':', 'NOT']

  class << self
    attr_reader :operators
  end

  def initialize(text)
    super
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.empty?

    type = type_stack.pop
    @arg_types = [type]

    @content_type = type
    type_stack.push(@content_type)
  end

  def set_shape(shape_stack)
    raise(BASICExpressionError, 'Not enough operands') if shape_stack.empty?

    @shape = shape_stack.pop

    @arg_shapes = [@shape]

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    raise(BASICExpressionError, 'Not enough operands') if constant_stack.empty?

    @constant = constant_stack.pop

    constant_stack.push(@constant)
  end

  def pop_stack(stack)
    stack.pop
  end

  def unary?
    true
  end

  def binary?
    false
  end
end

# Binary scalar operators
class BinaryOperator < Operator
  @operators = [
    '=', '<>', '><', '>', '>=', '=>', '<', '<=', '=<',
    '+', '-', '*', '/', '^', '**',
    'AND', 'OR'
  ]

  class << self
    attr_reader :operators
  end

  def initialize(text)
    super
  end

  # set_content() is in each subclass

  def set_shape(shape_stack)
    raise(BASICExpressionError, 'Not enough operands') if
      shape_stack.size < 2

    b_shape = shape_stack.pop
    a_shape = shape_stack.pop

    @arg_shapes = [a_shape, b_shape]

    table =
      {
        %i[scalar scalar] => :scalar,
        %i[scalar array] => :array,
        %i[scalar matrix] => :matrix,
        %i[array scalar] => :array,
        %i[array array] => :array,
        %i[array matrix] => nil,
        %i[matrix scalar] => :matrix,
        %i[matrix array] => nil,
        %i[matrix matrix] => :matrix
      }

    @shape = table[[a_shape, b_shape]]

    if @shape.nil?
      raise(BASICExpressionError,
            "Bad expression #{a_shape} #{@op} #{b_shape}")
    end

    shape_stack.push(@shape)
  end

  def set_constant(constant_stack)
    raise(BASICExpressionError, 'Not enough operands') if
      constant_stack.size < 2

    b_const = constant_stack.pop
    a_const = constant_stack.pop

    @constant = a_const && b_const

    constant_stack.push(@constant)
  end

  def pop_stack(stack)
    stack.pop
    stack.pop
  end

  def unary?
    false
  end

  def binary?
    true
  end

  def evaluate(_interpreter, arg_stack)
    raise(BASICExpressionError, 'Not enough operands') if arg_stack.size < 2

    y = arg_stack.pop
    x = arg_stack.pop

    return @cached unless @cached.nil?

    res = if x.matrix? && y.matrix?
            matrix_matrix(x, y)
          elsif x.matrix? && y.scalar?
            matrix_scalar(x, y)
          elsif x.scalar? && y.matrix?
            scalar_matrix(x, y)
          elsif x.array? && y.array?
            array_array(x, y)
          elsif x.array? && y.scalar?
            array_scalar(x, y)
          elsif x.scalar? && y.array?
            scalar_array(x, y)
          else
            op_scalar_scalar(x, y)
          end

    @cached = res if @constant && $options['cache_const_expr']
    res
  end

  private

  def matrix_matrix(x, y)
    op_matrix_matrix(@operation, x, y)
  end

  def matrix_scalar(x, y)
    op_matrix_scalar(@operation, x, y)
  end

  def scalar_matrix(x, y)
    op_scalar_matrix(@operation, x, y)
  end

  def array_array(x, y)
    op_array_array(@operation, x, y)
  end

  def array_scalar(x, y)
    op_array_scalar(@operation, x, y)
  end

  def scalar_array(x, y)
    op_scalar_array(@operation, x, y)
  end

  def op_scalar_scalar(x, y)
    x.public_send(@operation, y)
  end

  def compatible(type1, type2)
    return true if type1 == type2

    numerics = %i[numeric integer boolean]

    return true if numerics.include?(type1) && numerics.include?(type2)

    false
  end

  def result_type(type1, type2)
    return type1 if type1 == type2

    return :string if type1 == :string

    return :numeric if type1 == :numeric
    return :numeric if type2 == :numeric

    return :integer if type1 == :integer
    return :integer if type2 == :integer

    :boolean
  end

  def op_scalar_matrix_1(op, a, b)
    dims = b.dimensions
    n_cols = dims[0].to_i
    values = {}
    base = $options['base'].value

    (base..n_cols).each do |col|
      b_value = b.get_value_1(col)
      coords = AbstractElement.make_coord(col)
      values[coords] = a.send(op, b_value)
    end

    values
  end

  def op_scalar_matrix_2(op, a, b)
    dims = b.dimensions
    n_rows = dims[0].to_i
    n_cols = dims[1].to_i
    values = {}
    base = $options['base'].value

    (base..n_rows).each do |row|
      (base..n_cols).each do |col|
        b_value = b.get_value_2(row, col)
        coords = AbstractElement.make_coords(row, col)
        values[coords] = a.send(op, b_value)
      end
    end

    values
  end

  def op_scalar_matrix(op, a, b)
    dims = b.dimensions
    values = op_scalar_matrix_1(op, a, b) if dims.size == 1
    values = op_scalar_matrix_2(op, a, b) if dims.size == 2

    Matrix.new(dims, values)
  end

  def op_matrix_scalar_1(op, a, b)
    dims = a.dimensions
    n_cols = dims[0].to_i
    values = {}
    base = $options['base'].value

    (base..n_cols).each do |col|
      a_value = a.get_value_1(col)
      coords = AbstractElement.make_coord(col)
      values[coords] = a_value.send(op, b)
    end

    values
  end

  def op_matrix_scalar_2(op, a, b)
    dims = a.dimensions
    n_rows = dims[0].to_i
    n_cols = dims[1].to_i
    values = {}
    base = $options['base'].value

    (base..n_rows).each do |row|
      (base..n_cols).each do |col|
        a_value = a.get_value_2(row, col)
        coords = AbstractElement.make_coords(row, col)
        values[coords] = a_value.send(op, b)
      end
    end

    values
  end

  def op_matrix_scalar(op, a, b)
    dims = a.dimensions
    values = op_matrix_scalar_1(op, a, b) if dims.size == 1
    values = op_matrix_scalar_2(op, a, b) if dims.size == 2

    Matrix.new(dims, values)
  end

  def add_matrix_matrix_1(a, b)
    a_dims = a.dimensions
    n_cols = a_dims[0].to_i
    values = {}
    base = $options['base'].value

    (base..n_cols).each do |col|
      a_value = a.get_value_1(col)
      b_value = b.get_value_1(col)
      coords = AbstractElement.make_coord(col)
      values[coords] = a_value.send(:add, b_value)
    end

    values
  end

  def add_matrix_matrix_2(a, b)
    a_dims = a.dimensions
    n_rows = a_dims[0].to_i
    n_cols = a_dims[1].to_i
    values = {}
    base = $options['base'].value

    (base..n_rows).each do |row|
      (base..n_cols).each do |col|
        a_value = a.get_value_2(row, col)
        b_value = b.get_value_2(row, col)
        coords = AbstractElement.make_coords(row, col)
        values[coords] = a_value.send(:add, b_value)
      end
    end

    values
  end

  def add_matrix_matrix(a, b)
    # verify dimensions match
    a_dims = a.dimensions
    b_dims = b.dimensions

    raise(BASICExpressionError, 'Matrix dimensions do not match') if
      a_dims != b_dims

    values = add_matrix_matrix_1(a, b) if a_dims.size == 1
    values = add_matrix_matrix_2(a, b) if a_dims.size == 2

    Matrix.new(a_dims, values)
  end

  def subtract_matrix_matrix_1(a, b)
    a_dims = a.dimensions
    n_cols = a_dims[0].to_i
    values = {}
    base = $options['base'].value

    (base..n_cols).each do |col|
      a_value = a.get_value_1(col)
      b_value = b.get_value_1(col)
      coords = AbstractElement.make_coord(col)
      values[coords] = a_value.send(:subtract, b_value)
    end

    values
  end

  def subtract_matrix_matrix_2(a, b)
    a_dims = a.dimensions
    n_rows = a_dims[0].to_i
    n_cols = a_dims[1].to_i
    values = {}
    base = $options['base'].value

    (base..n_rows).each do |row|
      (base..n_cols).each do |col|
        a_value = a.get_value_2(row, col)
        b_value = b.get_value_2(row, col)
        coords = AbstractElement.make_coords(row, col)
        values[coords] = a_value.send(:subtract, b_value)
      end
    end

    values
  end

  def subtract_matrix_matrix(a, b)
    # verify dimensions match
    a_dims = a.dimensions
    b_dims = b.dimensions

    raise(BASICExpressionError, 'Matrix dimensions do not match') if
      a_dims != b_dims

    values = subtract_matrix_matrix_1(a, b) if a_dims.size == 1
    values = subtract_matrix_matrix_2(a, b) if a_dims.size == 2

    Matrix.new(a_dims, values)
  end

  def array_to_horizontal(a)
    base = $options['base'].value
    a_dims = a.dimensions
    new_dims = [NumericValue.new(base), a_dims[0]]
    n_cols = a_dims[0].to_i
    new_values = {}

    (base..n_cols).each do |col|
      value = a.get_value_1(col)
      coords = AbstractElement.make_coords(base, col)
      new_values[coords] = value
    end

    Matrix.new(new_dims, new_values)
  end

  def horizontal_to_array(m)
    m_dims = m.dimensions
    new_dims = [m_dims[1]]
    new_values = {}
    n_cols = new_dims[0].to_i
    base = $options['base'].value
    row = base

    (base..n_cols).each do |col|
      value = m.get_value_2(row, col)
      coords = AbstractElement.make_coord(col)
      new_values[coords] = value
    end

    Matrix.new(new_dims, new_values)
  end

  def array_to_vertical(a)
    base = $options['base'].value
    a_dims = a.dimensions
    new_dims = [a_dims[0], NumericValue.new(base)]
    n_cols = a_dims[0].to_i
    new_values = {}

    (base..n_cols).each do |col|
      value = a.get_value_1(col)
      coords = AbstractElement.make_coords(col, base)
      new_values[coords] = value
    end

    Matrix.new(new_dims, new_values)
  end

  def vertical_to_array(m)
    m_dims = m.dimensions
    new_dims = [m_dims[0]]
    new_values = {}
    n_rows = new_dims[0].to_i
    base = $options['base'].value
    col = base

    (base..n_rows).each do |row|
      value = m.get_value_2(row, col)
      coords = AbstractElement.make_coord(row)
      new_values[coords] = value
    end

    Matrix.new(new_dims, new_values)
  end

  def multiply_matrix_matrix_value(a, b, r_row, r_col)
    a_dims = a.dimensions
    a_cols = a_dims[1].to_i
    f = 0
    base = $options['base'].value

    (base..a_cols).each do |a_col|
      a_value = a.get_value_2(r_row, a_col)
      b_value = b.get_value_2(a_col, r_col)
      f += a_value.to_f * b_value.to_f
    end

    NumericValue.new(f)
  end

  def multiply_matrix_matrix_work(a, b)
    r_dims = [a.dimensions[0], b.dimensions[1]]
    r_rows = r_dims[0].to_i
    r_cols = r_dims[1].to_i
    values = {}
    base = $options['base'].value

    (base..r_rows).each do |r_row|
      (base..r_cols).each do |r_col|
        coords = AbstractElement.make_coords(r_row, r_col)
        values[coords] = multiply_matrix_matrix_value(a, b, r_row, r_col)
      end
    end

    values
  end

  def multiply_matrix_matrix_2_2(a, b)
    a_dims = a.dimensions
    b_dims = b.dimensions

    # number of columns in a must match number of rows in b
    raise(BASICExpressionError, 'Matrix dimensions do not match') if
      a_dims[1] != b_dims[0]

    r_dims = [a_dims[0], b_dims[1]]
    values = multiply_matrix_matrix_work(a, b)

    Matrix.new(r_dims, values)
  end

  def multiply_matrix_matrix_2_1(a, b)
    a_dims = a.dimensions
    new_b = array_to_vertical(b)
    new_b_dims = new_b.dimensions

    # number of columns in a must match number of rows in b
    raise(BASICExpressionError, 'Matrix dimensions do not match') if
      a_dims[1] != new_b_dims[0]

    r_dims = [a_dims[0], new_b_dims[1]]
    values = multiply_matrix_matrix_work(a, new_b)
    m = Matrix.new(r_dims, values)

    vertical_to_array(m)
  end

  def multiply_matrix_matrix_1_2(a, b)
    new_a = array_to_horizontal(a)
    new_a_dims = new_a.dimensions
    b_dims = b.dimensions

    # number of columns in a must match number of rows in b
    raise(BASICExpressionError, 'Matrix dimensions do not match') if
      new_a_dims[1] != b_dims[0]

    r_dims = [new_a_dims[0], b_dims[1]]
    values = multiply_matrix_matrix_work(new_a, b)
    m = Matrix.new(r_dims, values)

    horizontal_to_array(m)
  end

  def multiply_matrix_matrix(a, b)
    dim_counts = [a.dimensions.size, b.dimensions.size]
    case dim_counts
    when [2, 1]
      multiply_matrix_matrix_2_1(a, b)
    when [1, 2]
      multiply_matrix_matrix_1_2(a, b)
    when [2, 2]
      multiply_matrix_matrix_2_2(a, b)
    else
      raise(BASICExpressionError,
            'Matrix multiplication must have two matrices')
    end
  end

  def divide_matrix_matrix(_, _)
    raise BASICExpressionError, 'Cannot divide matrix by matrix'
  end

  def power_matrix_matrix(_, _)
    raise BASICExpressionError, 'Cannot raise matrix to matrix power'
  end

  def op_array_array(op, a, b)
    base = $options['base'].value

    dims = b.dimensions

    raise BASICRuntimeError, :te_arr_dif_siz if a.dimensions != dims

    n_cols = dims[0].to_i
    values = {}

    (base..n_cols).each do |col|
      a_value = a.get_value_1(col)
      b_value = b.get_value_1(col)
      coords = AbstractElement.make_coord(col)
      values[coords] = a_value.send(op, b_value)
    end

    BASICArray.new(dims, values)
  end

  def op_scalar_array(op, a, b)
    base = $options['base'].value

    dims = b.dimensions
    n_cols = dims[0].to_i
    values = {}

    (base..n_cols).each do |col|
      b_value = b.get_value_1(col)
      coords = AbstractElement.make_coord(col)
      values[coords] = a.send(op, b_value)
    end

    BASICArray.new(dims, values)
  end

  def op_array_scalar(op, a, b)
    base = $options['base'].value

    dims = a.dimensions
    n_cols = dims[0].to_i
    values = {}

    (base..n_cols).each do |col|
      a_value = a.get_value_1(col)
      coords = AbstractElement.make_coord(col)
      values[coords] = a_value.send(op, b)
    end

    BASICArray.new(dims, values)
  end

  def op_matrix_matrix(op_sym, a, b)
    case op_sym
    when :add
      add_matrix_matrix(a, b)
    when :subtract
      subtract_matrix_matrix(a, b)
    when :multiply
      multiply_matrix_matrix(a, b)
    when :divide
      divide_matrix_matrix(a, b)
    when :power
      power_matrix_matrix(a, b)
    end
  end
end

# Initial operator
# not a real operator, used only for parsing
class InitialOperator < AbstractElement
  def initialize
    super

    @operator = true
    @terminal = true
    @precedence = 0
  end

  def to_s
    'INIT'
  end
end

# Terminal operator
# not a real operator, used only for parsing
class TerminalOperator < AbstractElement
  def initialize
    super

    @operator = true
    @terminal = true
    @precedence = 0
  end

  def to_s
    'TERM'
  end
end

class UnaryOperatorPlus < UnaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '+'
  end

  def initialize(text)
    super

    @precedence = 9
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.empty?

    type = type_stack.pop
    @arg_types = [type]

    arg_types = %i[numeric integer]

    raise(BASICExpressionError, "Type mismatch #{@op} #{type}") unless
      arg_types.include?(type)

    @content_type = type
    type_stack.push(@content_type)
  end

  def evaluate(_, arg_stack)
    raise(BASICExpressionError, 'Not enough operands') if arg_stack.empty?

    x = arg_stack.pop

    return @cached unless @cached.nil?

    res = x.posate

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

class UnaryOperatorMinus < UnaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '-'
  end

  def initialize(text)
    super

    @precedence = 9
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.empty?

    type = type_stack.pop
    @arg_types = [type]

    arg_types = %i[numeric integer]

    raise(BASICExpressionError, "Type mismatch #{@op} #{type}") unless
      arg_types.include?(type)

    @content_type = type
    type_stack.push(@content_type)
  end

  def evaluate(_, arg_stack)
    raise(BASICExpressionError, 'Not enough operands') if arg_stack.empty?

    x = arg_stack.pop

    return @cached unless @cached.nil?

    res = x.negate

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

class UnaryOperatorHash < UnaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '#'
  end

  def initialize(text)
    super

    @content_type = :filehandle
    @precedence = 9
  end

  def pound?
    true
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.empty?

    type = type_stack.pop
    @arg_types = [type]

    arg_types = %i[numeric integer]

    raise(BASICExpressionError, "Type mismatch #{@op} #{type}") unless
      arg_types.include?(type)

    @content_type = :filehandle
    type_stack.push(@content_type)
  end

  def evaluate(_, arg_stack)
    raise(BASICExpressionError, 'Not enough operands') if arg_stack.empty?

    x = arg_stack.pop

    return @cached unless @cached.nil?

    res = x.filehandle

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

class UnaryOperatorNot < UnaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == 'NOT'
  end

  def initialize(text)
    super

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    @precedence = 9
  end

  def pound?
    true
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.empty?

    type = type_stack.pop
    @arg_types = [type]

    arg_types = %i[numeric integer boolean string]

    raise(BASICExpressionError, "Type mismatch #{@op} #{type}") unless
      arg_types.include?(type)

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    type_stack.push(@content_type)
  end

  def evaluate(_, arg_stack)
    raise(BASICExpressionError, 'Not enough operands') if arg_stack.empty?

    x = arg_stack.pop

    return @cached unless @cached.nil?

    res = x.not

    @cached = res if @constant && $options['cache_const_expr']
    res
  end
end

class BinaryOperatorPlus < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '+'
  end

  def initialize(text)
    super

    @operation = :add
    @precedence = 6
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer string]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = result_type(a_type, b_type)
    type_stack.push(@content_type)
  end
end

class BinaryOperatorMinus < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '-'
  end

  def initialize(text)
    super

    @operation = :subtract
    @precedence = 6
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = result_type(a_type, b_type)
    type_stack.push(@content_type)
  end
end

class BinaryOperatorMultiply < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '*'
  end

  def initialize(text)
    super

    @operation = :multiply
    @precedence = 7
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_1_types = %i[numeric integer string]
    arg_2_types = %i[numeric integer]

    arg_1_types = %i[numeric integer string]
    arg_2_types = %i[numeric integer]

    unless arg_1_types.include?(a_type) && arg_2_types.include?(b_type)
      raise(BASICExpressionError,
            "Type mismatch #{a_type} #{@op} #{b_type}")
    end

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = result_type(a_type, b_type)
    type_stack.push(@content_type)
  end
end

class BinaryOperatorDivide < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '/'
  end

  def initialize(text)
    super

    @operation = :divide
    @precedence = 7
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = result_type(a_type, b_type)
    type_stack.push(@content_type)
  end
end

class BinaryOperatorPower < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) &&
      (token.to_s == '^' || token.to_s == '**')
  end

  def initialize(text)
    super

    @operation = :power
    @precedence = 8
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @content_type = result_type(a_type, b_type)
    type_stack.push(@content_type)
  end
end

class BinaryOperatorEqual < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '='
  end

  def initialize(text)
    super

    @operation = :b_eq
    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    @precedence = 4
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer string boolean]

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    type_stack.push(@content_type)
  end
end

class BinaryOperatorNotEqual < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) &&
      (token.to_s == '<>' || token.to_s == '><')
  end

  def initialize(text)
    super

    @operation = :b_ne
    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    @precedence = 4
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer string boolean]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    type_stack.push(@content_type)
  end
end

class BinaryOperatorLess < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '<'
  end

  def initialize(text)
    super

    @operation = :b_lt
    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    @precedence = 4
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer string]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    type_stack.push(@content_type)
  end
end

class BinaryOperatorLessEqual < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) &&
      (token.to_s == '<=' || token.to_s == '=<')
  end

  def initialize(text)
    super

    @operation = :b_le
    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    @precedence = 4
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer string]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    type_stack.push(@content_type)
  end
end

class BinaryOperatorGreater < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == '>'
  end

  def initialize(text)
    super

    @operation = :b_gt
    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    @precedence = 4
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer string]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    type_stack.push(@content_type)
  end
end

class BinaryOperatorGreaterEqual < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) &&
      (token.to_s == '>=' || token.to_s == '=>')
  end

  def initialize(text)
    super

    @operation = :b_ge
    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    @precedence = 4
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer string]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type) ||
      !compatible(a_type, b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    type_stack.push(@content_type)
  end
end

class BinaryOperatorAnd < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == 'AND'
  end

  def initialize(text)
    super

    @operation = :b_and
    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    @precedence = 3
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer string boolean]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    type_stack.push(@content_type)
  end
end

class BinaryOperatorOr < BinaryOperator
  def self.accept?(token)
    classes = %w[OperatorToken]
    classes.include?(token.class.to_s) && token.to_s == 'OR'
  end

  def initialize(text)
    super

    @operation = :b_or
    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    @precedence = 2
  end

  def set_content_type(type_stack)
    raise(BASICExpressionError, 'Not enough operands') if type_stack.size < 2

    b_type = type_stack.pop
    a_type = type_stack.pop
    @arg_types = [a_type, b_type]

    arg_types = %i[numeric integer string boolean]

    raise(BASICExpressionError, "Type mismatch #{a_type} #{@op} #{b_type}") if
      !arg_types.include?(a_type) || !arg_types.include?(b_type)

    @warnings << "Type mismatch #{a_type} #{@op} #{b_type}" if
      a_type != b_type

    @content_type = :boolean
    @content_type = :integer if $options['relational_result'].value == 'INTEGER'
    @content_type = :numeric if $options['relational_result'].value == 'NUMERIC'
    type_stack.push(@content_type)
  end
end
