# Statement factory class
class StatementFactory
  include Singleton

  attr_writer :tokenbuilders

  def initialize
    @statement_definitions = statement_definitions
    @tokenbuilders = []
  end

  def parse(text)
    line_number = nil
    line = nil
    m = /\A\d+/.match(text)

    unless m.nil?
      number = NumericConstantToken.new(m[0])
      line_number = LineNumber.new(number)
      line_text = m.post_match
      all_tokens = tokenize(line_text)
      all_tokens.delete_if(&:whitespace?)
      comment = nil
      comment = all_tokens.pop if
        !all_tokens.empty? && all_tokens[-1].comment?

      line = create(line_text, all_tokens, comment, line_number)
    end

    [line_number, line]
  end

  def create_statement(statement_tokens)
    if statement_tokens.empty?
      statement = EmptyStatement.new
    else
      statement = nil

      keywords, tokens = extract_keywords(statement_tokens)

      while statement.nil?
        if @statement_definitions.key?(keywords)
          tokens_lists = split_keywords(tokens)

          statement =
            @statement_definitions[keywords].new(keywords, tokens_lists)
        else
          if keywords.empty?
            statement = UnknownStatement.new(text) if statement.nil?
          else
            keyword = keywords.pop
            tokens.unshift(keyword)
          end
        end
      end
    end

    statement
  end

  private

  def split_on_statement_separators(tokens)
    tokens_lists = []
    statement_tokens = []
    tokens.each do |token|
      if token.statement_separator?
        tokens_lists << statement_tokens
        statement_tokens = []
      else
        statement_tokens << token
      end
    end
    tokens_lists << statement_tokens unless statement_tokens.empty?
    tokens_lists
  end

  public

  def create(text, all_tokens, comment, _)
    statements = []
    statements_tokens = split_on_statement_separators(all_tokens)

    if statements_tokens.empty?
      statement = EmptyStatement.new
      statements << statement
    else
      statement_index = 0
      statements_tokens.each do |statement_tokens|
        statement = UnknownStatement.new(text)

        begin
          statement = create_statement(statement_tokens)
        rescue BASICExpressionError, BASICRuntimeError => e
          statement = InvalidStatement.new(text, all_tokens, e)
        end

        statements << statement
        statement_index += 1
      end
    end

    Line.new(text, statements, all_tokens, comment)
  end

  def keywords_definitions
    keywords = []

    statement_classes.each do |cl|
      kwds = cl.lead_keywords.flatten
      kwds.each { |kwd| keywords << kwd.to_s }

      keywords += cl.extra_keywords
    end

    keywords.uniq
  end

  private

  def statement_classes
    [
      ArrPrintStatement,
      ArrReadStatement,
      ArrWriteStatement,
      ArrLetStatement,
      ChainStatement,
      ChangeStatement,
      CloseStatement,
      DataStatement,
      DefineFunctionStatement,
      DimStatement,
      EndStatement,
      FnendStatement,
      ForStatement,
      GosubStatement,
      GotoStatement,
      IfStatement,
      InputStatement,
      LetStatement,
      LetLessStatement,
      LineInputStatement,
      MatPrintStatement,
      MatReadStatement,
      MatWriteStatement,
      MatLetStatement,
      NextStatement,
      OnStatement,
      OnErrorStatement,
      OpenStatement,
      OptionStatement,
      PrintStatement,
      PrintUsingStatement,
      RandomizeStatement,
      ReadStatement,
      RemarkStatement,
      RestoreStatement,
      ResumeStatement,
      ReturnStatement,
      SleepStatement,
      StopStatement,
      WriteStatement
    ]
  end

  def statement_definitions
    lead_keywords = {}

    statement_classes.each do |class_name|
      keyword_sets = class_name.lead_keywords
      keyword_sets.each do |set|
        lead_keywords[set] = class_name
      end
    end

    lead_keywords
  end

  def extract_keywords(all_tokens)
    keywords = []
    tokens = []
    saw_non_keyword = false

    all_tokens.each do |token|
      saw_non_keyword = true unless token.keyword?
      keywords << token unless saw_non_keyword
      tokens << token if saw_non_keyword
    end

    [keywords, tokens]
  end

  def split_keywords(tokens)
    results = []
    nonkeywords = []

    tokens.each do |token|
      if token.keyword?
        results << nonkeywords unless nonkeywords.empty?
        nonkeywords = []
        results << token
      else
        nonkeywords << token
      end
    end

    results << nonkeywords unless nonkeywords.empty?

    results
  end

  def tokenize(text)
    invalid_tokenbuilder = InvalidTokenBuilder.new
    tokenizer = Tokenizer.new(@tokenbuilders, invalid_tokenbuilder)
    tokenizer.tokenize(text)
  end
end

# parent of all statement classes
class AbstractStatement
  attr_reader :errors
  attr_reader :keywords
  attr_reader :tokens
  attr_accessor :part_of_user_function

  def self.extra_keywords
    []
  end

  def initialize(keywords, tokens_lists)
    @keywords = keywords
    @tokens = tokens_lists.flatten
    @errors = []
    @modifiers = []
    @profile_count = 0
    @profile_time = 0
    @part_of_user_function = nil
  end

  private

  def extract_modifiers(tokens_lists)
    modifier_added = true
    modifier_added = make_modifier(tokens_lists) while modifier_added
    @modifiers.each { |modifier| @errors += modifier.errors }
  end

  public

  def pretty
    list = [AbstractToken.pretty_tokens(@keywords, @tokens)]
    @modifiers.each { |modifier| list << modifier.pretty }

    list.join(' ')
  end

  def dump
    ['Unimplemented']
  end

  def print_errors(console_io)
    @errors.each { |error| console_io.print_line(' ' + error) }
  end

  def program_check(_, _, _)
    true
  end

  def preexecute_a_statement(line_number, interpreter, console_io)
    if errors.empty?
      pre_execute(interpreter)
    else
      interpreter.stop_running
      console_io.print_line("Errors in line #{line_number}:")
      print_errors(console_io)
    end

    errors.empty?
  end

  private

  def pre_execute(_) end

  public

  def reset_profile_metrics
    @profile_count = 0
    @profile_time = 0
  end

  def profile
    text = AbstractToken.pretty_tokens(@keywords, @tokens)
    ' (' + @profile_time.round(3).to_s + '/' + @profile_count.to_s + ')' + text
    ### TODO: add profile for modifiers
  end

  def renumber(_) end

  def numerics
    nums = []

    # convert a sequence of minus sign and numeric token to a single token
    # the result list should be a list of tokens, not expressions
    # and we want a unary minus and value to render as number in crossref
    negate = false
    prev_unary_minus = false
    prev_operand = false

    @tokens.each do |token|
      negate = !negate if prev_unary_minus

      if token.numeric_constant? && !token.symbol_constant?
        if negate
          nums << token.clone.negate
        else
          nums << token
        end
      end

      prev_unary_minus = token.operator? && token.to_s == '-' && !prev_operand
      prev_operand =
        token.groupend? ||
        token.numeric_constant? ||
        token.variable?
    end

    nums
  end

  def numeric_symbol_constants
    syms = @tokens.clone
    syms.keep_if(&:symbol_constant?)
    syms.keep_if(&:numeric_constant?)
  end

  def strings
    strs = @tokens.clone
    strs.keep_if(&:text_constant?)
    strs.delete_if(&:symbol_constant?)
  end

  def text_symbol_constants
    syms = @tokens.clone
    syms.keep_if(&:symbol_constant?)
    syms.keep_if(&:text_constant?)
  end

  def functions
    funcs = @tokens.clone
    funcs.keep_if(&:function?)
    funcs.map(&:to_s)
  end

  def userfuncs
    udfs = @tokens.clone
    udfs.keep_if(&:user_function?)
    udfs.map(&:to_s)
  end

  def variables
    vars = @tokens.clone
    vars.keep_if(&:variable?)
    vars.map(&:to_s)
  end

  private

  def execute(interpreter)
    current_line_index = interpreter.current_line_index
    index = current_line_index.index
    execute_premodifier(interpreter) if index < 0
    execute_core(interpreter) if index.zero?
    execute_postmodifier(interpreter) if index > 0
  end

  def print_trace_info(trace_out, current_line_index)
    trace_out.newline_when_needed

    unless @part_of_user_function.nil?
      trace_out.print_out '(' + @part_of_user_function.to_s + ') '
    end

    trace_out.print_out current_line_index.to_s + ':' + pretty
    trace_out.newline
  end

  public

  def execute_a_statement(interpreter, trace_out, current_line_index,
                          function_running)
    print_trace_info(trace_out, current_line_index)

    if part_of_user_function.nil? || function_running
      if @part_of_user_function != interpreter.current_user_function
        raise(BASICRuntimeError, 'Invalid transfer in/out of function')
      end

      timing = Benchmark.measure { execute(interpreter) }
      user_time = timing.utime + timing.cutime
      sys_time = timing.stime + timing.cstime
      time = user_time + sys_time
      @profile_time += time
      @profile_count += 1
    else
      trace_out.print_line(' Line ignored')
    end
  end

  def start_index
    0 - @modifiers.size
  end

  def last_index
    @modifiers.size
  end

  def multidef?
    false
  end

  def multiend?
    false
  end

  private

  def make_modifier(tokens_lists)
    template_if = ['IF', [1, '=']]
    if tokens_lists.size > 2 &&
       check_template(tokens_lists.last(2), template_if)

      # create the modifier
      modifier_tokens = tokens_lists.last
      modifier = IfModifier.new(modifier_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(2)

      return true
    end

    template_for_to = ['FOR', [1, '>='], 'TO', [1, '>=']]
    template_for_to_step = ['FOR', [1, '>='], 'TO', [1, '='], 'STEP', [1, '>=']]

    if tokens_lists.size > 4 &&
       check_template(tokens_lists.last(4), template_for_to)

      # create the modifer
      control_and_start_tokens = tokens_lists[-3]
      end_tokens = tokens_lists.last
      modifier = ForModifier.new(control_and_start_tokens, end_tokens, nil)
      @modifiers << modifier

      # remove the tokens used for the modifier
      tokens_lists.pop(4)

      return true
    end

    if tokens_lists.size > 6 &&
       check_template(tokens_lists.last(6), template_for_to_step)

      # create the modifer
      control_and_start_tokens = tokens_lists[-5]
      end_tokens = tokens_lists[-3]
      step_tokens = tokens_lists.last
      modifier =
        ForModifier.new(control_and_start_tokens, end_tokens, step_tokens)
      @modifiers << modifier

      # remove the tokens used for the modifier
      tokens_lists.pop(6)

      return true
    end

    false
  end

  def execute_premodifier(interpreter)
    current_line_index = interpreter.current_line_index
    index = 0 - (current_line_index.index + 1)
    modifier = @modifiers[index]
    modifier.execute_pre(interpreter)
  end

  def execute_postmodifier(interpreter)
    current_line_index = interpreter.current_line_index
    index = current_line_index.index - 1
    modifier = @modifiers[index]
    modifier.execute_post(interpreter)
  end

  protected

  def check_template(tokens_lists, template)
    return false unless tokens_lists.size == template.size

    result = true
    pairs = template.zip(tokens_lists)

    pairs.each do |pair|
      control = pair[0]
      value = pair[1]

      if control.class.to_s == 'Array' &&
         value.class.to_s == 'Array'

        # control array and value array implies an expression
        result &= value.size == control[0] if control.size == 1
        result &= value.size >= control[0] if
          control.size == 2 && control[1] == '>='
        
      elsif control.class.to_s == 'Array' &&
            value.class.to_s == 'KeywordToken'

        # control array and single value (not array of one) implies
        # multiple possible keywords
        result &= control.include?(value.to_s)

      elsif control.class.to_s == 'String' &&
            value.class.to_s == 'KeywordToken'

        # single control and single value is a specific keyword
        result &= value.to_s == control

      else
        result = false
      end
    end

    result
  end

  def split_tokens(tokens, want_separators)
    lists = []
    list = []
    parens_level = 0

    tokens.each do |token|
      if token.operand? &&
         (!list.empty? && (list[-1].operand? || list[-1].groupend?))
        lists << list unless list.empty?
        list = [token]
      elsif token.separator? && parens_level.zero?
        lists << list unless list.empty?
        lists << token if want_separators
        list = []
      else
        list << token
      end
      parens_level += 1 if token.groupstart?
      parens_level -= 1 if token.groupend? && !parens_level.zero?
    end

    lists << list unless list.empty?

    lists
  end

  def split_on_token(tokens, token_to_split)
    results = []
    list = []

    tokens.each do |token|
      if token.to_s != token_to_split
        list << token
      else
        results << list unless list.empty?
        list = []
        results << token
      end
    end

    results << list unless list.empty?

    results
  end

  def split_keywords(tokens)
    results = []
    nonkeywords = []

    tokens.each do |token|
      if token.keyword?
        results << nonkeywords unless nonkeywords.empty?
        nonkeywords = []
        results << token
      else
        nonkeywords << token
      end
    end

    results << nonkeywords unless nonkeywords.empty?

    results
  end

  def split_on_group_separators(tokens)
    tokens_lists = []
    statement_tokens = []

    # set to TRUE, so an empty list creates one empty token
    last_was_separator = true

    tokens.each do |token|
      if token.separator?
        tokens_lists << statement_tokens
        statement_tokens = []
        last_was_separator = true
      else
        statement_tokens << token
        last_was_separator = false
      end
    end

    tokens_lists << statement_tokens if
      !statement_tokens.empty? || last_was_separator
    tokens_lists
  end

  def make_coord(c)
    [NumericConstant.new(c)]
  end

  def make_coords(r, c)
    [NumericConstant.new(r), NumericConstant.new(c)]
  end
end

# unparsed statement
class InvalidStatement < AbstractStatement
  def initialize(text, all_tokens, error)
    super([], all_tokens)

    @text = text
    @errors << 'Invalid statement: ' + error.message
  end

  def to_s
    @text
  end

  def pre_execute(_)
    raise(BASICRuntimeError, @errors[0])
  end

  def execute_core(_)
    raise(BASICRuntimeError, @errors[0])
  end
end

# unknown statement
class UnknownStatement < AbstractStatement
  def initialize(text)
    super([], [])

    @text = text
    @errors << "Unknown statement '#{text.strip}'"
  end

  def to_s
    @text
  end

  def execute_core(_) end
end

# empty statement (line number only)
class EmptyStatement < AbstractStatement
  def initialize
    super([], [])
  end

  def dump
    []
  end

  def to_s
    ''
  end

  def execute_core(_) end
end

# REMARK
class RemarkStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('REMARK')],
      [KeywordToken.new('REM')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    @rest = Remark.new(nil)
    @rest = Remark.new(tokens_lists[0]) unless tokens_lists.empty?
  end

  def dump
    [@rest.dump]
  end

  def execute_core(_) end
end

# common functions for IO statements
module FileFunctions
  def extract_file_handle(print_items)
    print_items = print_items.clone
    file_tokens = nil

    unless print_items.empty? ||
           print_items[0].carriage_control?

      candidate_file_tokens = print_items[0]

      if candidate_file_tokens.filehandle?
        file_tokens = print_items.shift

        print_items.shift if
          !print_items.empty? &&
          print_items[0].carriage_control?
      end
    end

    [file_tokens, print_items]
  end

  def get_file_handle(interpreter, file_tokens)
    return nil if file_tokens.nil?

    file_handles = file_tokens.evaluate(interpreter)
    file_handles[0]
  end

  def add_implied_items(print_items, final)
    print_items << CarriageControl.new('NL') if print_items.empty?
    print_items << final if print_items[-1].printable?
  end
end

# common functions for INPUT statements
module InputFunctions
  def dump
    lines = []
    @input_items.each { |item| lines += item.dump } unless @input_items.nil?
    lines
  end

  def variables
    vars = []
    vars += @file_tokens.variables unless @file_tokens.nil?
    @input_items.each { |item| vars += item.variables } unless @input_items.nil?
    vars
  end

  private

  def extract_prompt(print_items)
    print_items = print_items.clone
    prompt = nil

    unless print_items.empty? ||
           print_items[0].carriage_control?

      candidate_prompt_tokens = print_items[0]

      if candidate_prompt_tokens.text_constant?
        prompt = print_items.shift

        print_items.shift if
          !print_items.empty? &&
          print_items[0].carriage_control?
      end
    end

    [prompt, print_items]
  end

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(print_items, tokens_list)
      end
    end

    print_items
  end

  def add_expression(print_items, tokens)
    if tokens[0].operator? && tokens[0].to_s == '#'
      print_items << ValueScalarExpression.new(tokens)
    elsif tokens[0].text_constant?
      print_items << ValueScalarExpression.new(tokens)
    else
      print_items << TargetExpression.new(tokens, ScalarReference)
    end

  rescue BASICExpressionError
    line_text = tokens.map(&:to_s).join
    @errors << 'Syntax error: "' + line_text + '" is not a value or operator'
  end

  def zip(names, values)
    raise(BASICRuntimeError, 'Too few items') if values.size < names.size

    results = []
    (0...names.size).each do |i|
      results << { 'name' => names[i], 'value' => values[i] }
    end

    results
  end
end

# CHAIN
class ChainStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('CHAIN')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>']]

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)

    target_tokens = tokens_lists[0]
    @target = ValueScalarExpression.new(target_tokens)
  end

  def dump
    ['']
  end

  def execute_core(interpreter)
    target_values = @target.evaluate(interpreter)
    target_value = target_values[0]

    raise(BASICExpressionError, "Target must be text item.") unless
      target_value.text_constant?

    interpreter.chain(target_values)
  end
end

# CHANGE
class ChangeStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('CHANGE')]
    ]
  end

  def self.extra_keywords
    ['TO']
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>='], 'TO', [1, '=']]

    if check_template(tokens_lists, template)
      source_tokens = tokens_lists[0]
      target_tokens = tokens_lists[2]

      @source = ValueScalarExpression.new(source_tokens)

      case @source.content_type
      when 'string'
        # string to array
        @target = TargetExpression.new(target_tokens, ArrayReference)
      when 'numeric'
        # array to string
        @target = TargetExpression.new(target_tokens, ScalarReference)
      else
        raise BASICExpressionError, 'Type mismatch'
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    lines += @source.dump unless @source.nil?
    lines += @target.dump unless @target.nil?

    lines
  end

  def execute_core(interpreter)
    source_values = @source.evaluate(interpreter)
    source_value = source_values[0]

    if source_value.text_constant?
      # string to array

      array = source_value.unpack
      dims = array.dimensions

      target_variable_token = VariableToken.new(@target.to_s)
      target_variable_name = VariableName.new(target_variable_token)
      target_variable = Reference.new(target_variable_name)
      interpreter.set_dimensions(target_variable, dims)

      values = array.values(interpreter)
      interpreter.set_values(target_variable_name, values)

    elsif source_value.numeric_constant?
      # array to string
      source_variable_token = VariableToken.new(@source.to_s)
      source_variable_name = VariableName.new(source_variable_token)

      target_values = @target.evaluate(interpreter)
      target_value = target_values[0]

      dims = interpreter.get_dimensions(source_variable_name)

      raise(BASICRuntimeError, 'Source not an array') if dims.nil?

      raise(BASICRuntimeError, 'Source must have 1 dimension') unless
        dims.size == 1

      cols = dims[0].to_i
      values = {}
      (0..cols).each do |col|
        column = IntegerConstant.new(col)
        variable = Value.new(source_variable_name, [column])
        coord = make_coord(col)
        values[coord] = interpreter.get_value(variable)
      end
      array = BASICArray.new(dims, values)
      text = array.pack

      interpreter.set_value(target_value, text)

    else
      raise BASICExpressionError, 'Type mismatch'
    end
  end

  def variables
    vars = []
    vars += @source.variables unless @source.nil?
    vars += @target.variables unless @target.nil?

    vars
  end
end

# CLOSE
class CloseStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('CLOSE')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]
    template_file = ['FILE', [1, '>=']]

    @filenum_expression = []
    if check_template(tokens_lists, template) ||
       check_template(tokens_lists, template_file)
      @filenum_expression = ValueScalarExpression.new(tokens_lists[-1])
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    @filenum_expression.dump
  end

  def execute_core(interpreter)
    fns = @filenum_expression.evaluate(interpreter)
    fh = fns[0]

    case fh.class.to_s
    when 'Fixnum'
      fh = FileHandle.new(fh)
    when 'NumericConstant'
      fh = FileHandle.new(fh.to_i)
    when 'IntegerConstant'
      fh = FileHandle.new(fh.to_i)
    when 'FileHandle'
      fh = fns[0]
    else
      raise(BASICRuntimeError, "Invalid file number #{fh.class}:#{fh}")
    end

    interpreter.close_file(fh)
  end

  def variables
    @filenum_expression.variables
  end
end

# DATA
class DataStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('DATA')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      @expressions = ValueScalarExpression.new(tokens_lists[0])
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    @expressions.dump
  end

  def pre_execute(interpreter)
    ds = interpreter.get_data_store(nil)
    data_list = @expressions.evaluate(interpreter)
    ds.store(data_list)
  end

  def execute_core(_) end
end

# DEF FNx
class DefineFunctionStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('DEF')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      @definition = nil
      begin
        @definition = UserFunctionDefinition.new(tokens_lists[0])
      rescue BASICExpressionError => e
        @errors << e.message
      end
    else
      @errors << 'Syntax error'
    end
  end

  def multidef?
    return false if @definition.nil?

    @definition.multidef?
  end

  def function_name
    @definition.name
  end

  def dump
    lines = []
    lines += @definition.dump unless @definition.nil?

    lines
  end

  def pre_execute(interpreter)
    name = @definition.name
    interpreter.set_user_function(name, @definition)
  end

  def execute_core(_) end
end

# DIM
class DimStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('DIM')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    template = [[1, '>=']]

    @expression_list = []
    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], false)
      tokens_lists.each do |tokens_list|
        begin
          @expression_list <<
            TargetExpression.new(tokens_list, CompoundDeclaration)
        rescue BASICExpressionError
          @errors << 'Invalid variable ' + tokens_list.map(&:to_s).join
        end
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    @expression_list.each { |expression| lines += expression.dump }

    lines
  end

  def execute_core(interpreter)
    @expression_list.each do |expression|
      variables = expression.evaluate(interpreter)
      variable = variables[0]
      subscripts = variable.subscripts
      if subscripts.empty?
        raise BASICRuntimeError, 'DIM statement requires subscript range'
      end
      interpreter.set_dimensions(variable, subscripts)
    end
  end

  def variables
    vars = []

    @expression_list.each do |expression|
      vars += expression.variables
    end

    vars
  end
end

# END
class EndStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('END')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def dump
    ['']
  end

  def program_check(program, console_io, line_number_index)
    next_line = program.find_next_line_index(line_number_index)

    return true if next_line.nil?

    console_io.print_line("Statements after END in line #{line_number_index}")

    false
  end

  def execute_core(interpreter)
    io = interpreter.console_io
    io.newline_when_needed
    interpreter.stop
  end
end

# FNEND
class FnendStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('FNEND')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def multiend?
    true
  end

  def dump
    ['']
  end

  def execute_core(interpreter)
    interpreter.exit_user_function
  end
end

# FOR statement
class ForStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('FOR')]
    ]
  end

  def self.extra_keywords
    %w(TO STEP)
  end

  def initialize(keywords, tokens_lists)
    super

    template1 = [[1, '>='], 'TO', [1, '>=']]
    template2 = [[1, '>='], 'TO', [1, '>='], 'STEP', [1, '>=']]

    if check_template(tokens_lists, template1)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        @control = VariableName.new(tokens1[0])
        @start = ValueScalarExpression.new(tokens2)
        @end = ValueScalarExpression.new(tokens_lists[2])
        @step_value = ValueScalarExpression.new([NumericConstantToken.new(1)])
      rescue BASICExpressionError => e
        @errors << e.message
      end
    elsif check_template(tokens_lists, template2)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        @control = VariableName.new(tokens1[0])
        @start = ValueScalarExpression.new(tokens2)
        @end = ValueScalarExpression.new(tokens_lists[2])
        @step_value = ValueScalarExpression.new(tokens_lists[4])
      rescue BASICExpressionError => e
        @errors << e.message
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    lines << 'control: ' + @control.dump unless @control.nil?
    lines << 'start:   ' + @start.dump.to_s unless @start.nil?
    lines << 'end:     ' + @end.dump.to_s unless @end.nil?
    lines << 'step:    ' + @step_value.dump.to_s unless @step_value.nil?

    lines
  end

  def execute_core(interpreter)
    from = @start.evaluate(interpreter)[0]
    to = @end.evaluate(interpreter)[0]
    step = @step_value.evaluate(interpreter)[0]

    fornext_control = interpreter.assign_fornext(@control, from, to, step)
    interpreter.lock_variable(@control)
    interpreter.enter_fornext(@control)
    terminated = fornext_control.front_terminated?

    if terminated
      interpreter.next_line_index = interpreter.find_closing_next(@control)
      interpreter.unlock_variable(@control)
      interpreter.exit_fornext
    end

    io = interpreter.trace_out
    print_more_trace_info(io, from, to, step, terminated)
  end

  def variables
    vars = []
    vars << @control.to_s
    vars += @start.variables
    vars += @end.variables
    vars + @step_value.variables
  end

  private

  def control_and_start(tokens)
    parts = split_on_token(tokens, '=')
    raise(BASICExpressionError, 'Incorrect initialization') if
      parts.size != 3
    raise(BASICExpressionError, 'Incorrect initialization') if
      parts[1].to_s != '='

    @errors << 'Control variable must be a variable' unless
      parts[0][0].variable?

    [parts[0], parts[2]]
  end

  def print_more_trace_info(io, from, to, step, terminated)
    io.trace_output(" #{@start} = #{from}") unless @start.numeric_constant?
    io.trace_output(" #{@end} = #{to}") unless @end.numeric_constant?
    io.trace_output(" #{@step_value} = #{step}") unless @step_value.numeric_constant?
    io.trace_output(" terminated:#{terminated}")
  end
end

# GOSUB
class GosubStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('GOSUB')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1]]

    if check_template(tokens_lists, template)
      if tokens_lists[0][0].numeric_constant?
        @destination = LineNumber.new(tokens_lists[0][0])
      else
        @errors << "Invalid line number #{tokens_lists[0][0]}"
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    [@destination.dump]
  end

  def program_check(program, console_io, line_number_index)
    return true if program.line_number?(@destination)

    console_io.print_line(
      "Line number #{@destination} not found in line #{line_number_index}"
    )

    false
  end

  def execute_core(interpreter)
    line_number = @destination
    index = interpreter.statement_start_index(line_number, 0)

    raise(BASICRuntimeError, 'Line number not found') if index.nil?

    destination = LineNumberIndex.new(line_number, 0, index)
    interpreter.push_return(interpreter.next_line_index)
    interpreter.next_line_index = destination
  end

  def renumber(renumber_map)
    @destination = renumber_map[@destination]
    @tokens[-1] = NumericConstantToken.new(@destination.line_number)
  end
end

# GOTO
class GotoStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('GOTO')]
    ]
  end

  def self.extra_keywords
    ['OF']
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1]]
    @destination = nil

    if check_template(tokens_lists, template)
      if tokens_lists[0][0].numeric_constant?
        @destination = LineNumber.new(tokens_lists[0][0])
      else
        @errors << "Invalid line number #{tokens_lists[0][0]}"
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    lines << @destination.dump unless @destination.nil?

    lines
  end

  def program_check(program, console_io, line_number_index)
    retval = true

    unless @destination.nil? || program.line_number?(@destination)
      console_io.print_line(
        "Line number #{@destination} not found in line #{line_number_index}"
      )
      retval = false
    end

    retval
  end

  def execute_core(interpreter)
    unless @destination.nil?
      line_number = @destination
      index = interpreter.statement_start_index(line_number, 0)
      raise(BASICRuntimeError, 'Line number not found') if index.nil?
      destination = LineNumberIndex.new(line_number, 0, index)
      interpreter.next_line_index = destination
    end
  end

  def renumber(renumber_map)
    unless @destination.nil?
      @destination = renumber_map[@destination]
      @tokens[-1] = NumericConstantToken.new(@destination.line_number)
    end
  end
end

# IF/THEN
class IfStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('IF')]
    ]
  end

  def self.extra_keywords
    %w(THEN ELSE)
  end

  def initialize(keywords, tokens_lists)
    super

    if tokens_lists.class.to_s == 'Hash'
      @expression = parse_expression(tokens_lists['expr'])
      @destination, @statement = parse_target(tokens_lists['then'])
      @else_dest = nil
      @else_dest, @else_stmt = parse_target(tokens_lists['else']) if
        tokens_lists.key?('else')
    else
      begin
        stack = parse_if(tokens_lists)
        @expression = parse_expression(stack['expr'])
        @destination, @statement = parse_target(stack['then'])
        @else_dest = nil
        @else_dest, @else_stmt = parse_target(stack['else']) if
          stack.key?('else')
      rescue BASICExpressionError => e
        @errors << 'Syntax Error: ' + e.message
      end
    end
  end

  private

  def parse_if(tokens_lists)
    stack = []
    new_dict = { 'expr' => [], 'then' => [] }
    stack << new_dict
    dict = stack[-1]
    state = 1

    tokens_lists.each do |tokens_list|
      handled = false

      case state
      when 1
        if tokens_list == 'THEN'
          state = 2
        elsif tokens_list.class.to_s == 'KeywordToken'
          dict['expr'] << tokens_list
        else
          dict['expr'] += tokens_list
        end
        handled = true
      when 2
        unless handled
          if tokens_list == 'ELSE'
            dict['else'] = []
            state = 3
          elsif tokens_list == 'IF' && dict['then'].empty?
            new_dict = { 'expr' => [], 'then' => [] }
            dict['then'] = new_dict
            stack << new_dict
            dict = stack[-1]
            state = 1
          elsif tokens_list.class.to_s == 'KeywordToken'
            dict['then'] << tokens_list
          else
            dict['then'] += tokens_list
          end
          handled = true
        end
      when 3
        unless handled
          if tokens_list == 'ELSE'
            stack.pop
            # TODO: exit if stack.empty
            dict = stack[-1]
            dict['else'] = []
          elsif tokens_list == 'IF' && dict['else'].empty?
            new_dict = { 'expr' => [], 'then' => [] }
            dict['else'] = new_dict
            stack << new_dict
            dict = stack[-1]
            state = 1
          elsif tokens_list.class.to_s == 'KeywordToken'
            dict['else'] << tokens_list
          else
            dict['else'] += tokens_list
          end
          handled = true
        end
      when 4
        unless handled
          if dict['then'].empty?
            dict['then'] += tokens_list
          else
            raise(BASICSyntaxError, 'THEN without matching IF')
          end
          handled = true
        end
      end
    end

    stack[0]
  end

  def print_dict(dict)
    expr_s = '['
    x0 = dict['expr']

    x0.each do |x|
      if x.class.to_s == 'Array'
        expr_s += '[' + x.map(&:to_s).join(', ') + ']'
      else
        expr_s += x.to_s
      end
      expr_s += ', '
    end

    expr_s += ']'
    x1 = dict['then']

    if x1.class.to_s == 'Array'
      ax1 = []

      x1.each do |x|
        if x.class.to_s == 'Array'
          ax1 << '[' + x.map(&:to_s).join(', ') + ']'
        else
          ax1 << x.to_s
        end
      end

      then_s = '[' + ax1.join(', ') + ']'
    else
      then_s = 'DICT'
    end

    else_s = ''

    if dict.key?('else')
      x2 = dict['else']
      if x2.class.to_s == 'Array'
        ax2 = []

        x2.each do |x|
          if x.class.to_s == 'Array'
            ax2 << '[' + x.map(&:to_s).join(', ') + ']'
          else
            ax2 << x.to_s
          end
        end

        else_s = '[' + ax2.join(', ') + ']'
      else
        else_s = 'DICT'
      end
    end
  end

  public

  def dump
    lines = []
    lines += @expression.dump unless @expression.nil?
    lines += @statement.dump unless @statement.nil?
    lines += @else_stmt.dump unless @else_stmt.nil?
    lines
  end

  def program_check(program, console_io, line_number_index)
    retval = true

    if @destination.nil? && @statement.nil?
      console_io.print_line("Invalid or missing line number in line #{line_number}")
    end

    unless @destination.nil? || program.line_number?(@destination)
      console_io.print_line(
        "Line number #{@destination} not found in line #{line_number_index}"
      )
      retval = false
    end

    unless @else_dest.nil? || program.line_number?(@else_dest)
      console_io.print_line(
        "Line number #{@else_dest} not found in line #{line_number_index}"
      )
      retval = false
    end

    retval
  end

  def execute_core(interpreter)
    values = @expression.evaluate(interpreter)

    raise(BASICExpressionError, 'Too many or too few values') unless
      values.size == 1

    result = values[0]

    result = BooleanConstant.new(result) unless
      result.class.to_s == 'BooleanConstant'

    if result.value
      unless @destination.nil?
        line_number = @destination
        index = interpreter.statement_start_index(line_number, 0)

        raise(BASICRuntimeError, 'Line number not found') if index.nil?

        destination = LineNumberIndex.new(line_number, 0, index)
        interpreter.next_line_index = destination
      end

      @statement.execute_core(interpreter) unless @statement.nil?
    else
      unless @else_dest.nil?
        line_number = @else_dest
        index = interpreter.statement_start_index(line_number, 0)

        raise(BASICRuntimeError, 'Line number not found') if index.nil?

        destination = LineNumberIndex.new(line_number, 0, index)
        interpreter.next_line_index = destination
      end

      if @else_dest.nil? && @else_stmt.nil? && interpreter.if_false_next_line
        # go to next numbered line, not next statement
        next_line_index = interpreter.find_next_line
        interpreter.next_line_index = next_line_index
      end

      @else_stmt.execute_core(interpreter) unless @else_stmt.nil?
    end

    s = ' ' + @expression.to_s + ': ' + result.to_s
    io = interpreter.trace_out
    io.trace_output(s)
  end

  def renumber(renumber_map)
    unless @destination.nil?
      @destination = renumber_map[@destination]
      index = 0
      i = 0

      @tokens.each do |token|
        index = i if token.to_s == 'THEN'
        i += 1
      end

      @tokens[index + 1] = NumericConstantToken.new(@destination.line_number)
    end

    return if @else_dest.nil?

    @else_dest = renumber_map[@else_dest]
    @tokens[-1] = NumericConstantToken.new(@else_dest.line_number)
  end

  def variables
    vars = []
    vars += @expression.variables unless @expression.nil?
    vars += @statement.variables unless @statement.nil?
    vars += @else_stmt.variables unless @else_stmt.nil?
    vars
  end

  private

  def parse_expression(tokens)
    expression = nil
    begin
      expression = ValueScalarExpression.new(tokens)
    rescue BASICExpressionError => e
      @errors << e.message
    end
    expression
  end

  def parse_target(tokens)
    destination = nil
    statement = nil

    if tokens.class.to_s == 'Hash'
      statement = IfStatement.new(nil, tokens)
    elsif tokens.size == 1 && tokens[0].numeric_constant?
      destination = LineNumber.new(tokens[0])
    else
      statement_factory = StatementFactory.instance
      statement = statement_factory.create_statement(tokens.flatten)
      @errors += statement.errors
    end

    [destination, statement]
  end
end

# INPUT
class InputStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('INPUT')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      input_items = split_tokens(tokens_lists[0], false)
      input_items = tokens_to_expressions(input_items)
      @file_tokens, input_items = extract_file_handle(input_items)
      @prompt, @input_items = extract_prompt(input_items)

      if !@input_items.empty? && @input_items[0].text_constant?
        @prompt = input_items[0]
        @input_items = @input_items[1..-1]
      end
    else
      @errors << 'Syntax error'
    end
  end

  include FileFunctions
  include InputFunctions

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :read)

    prompt = nil
    unless @prompt.nil?
      prompts = @prompt.evaluate(interpreter)
      prompt = prompts[0]
    end

    if fh.nil?
      values = input_values(fhr, interpreter, prompt, @input_items.size)
      fhr.implied_newline
    else
      values = fhr.input(interpreter)
    end

    raise(BASICRuntimeError, 'Not enough values') if
      values.size < @input_items.size

    name_value_pairs =
      zip(@input_items, values[0..@input_items.length])

    name_value_pairs.each do |hash|
      l_values = hash['name'].evaluate(interpreter)
      l_value = l_values[0]
      value = hash['value']
      interpreter.set_value(l_value, value)
    end
  end

  private

  def input_values(fhr, interpreter, prompt, count)
    values = []

    while values.size < count
      fhr.prompt(prompt)
      values += fhr.input(interpreter)

      prompt = nil
    end

    values
  end
end

# common functions for LET and LET-less statements
class AbstractLetStatement < AbstractStatement
  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[3, '>=']]

    if check_template(tokens_lists, template)
      begin
        @assignment = ScalarAssignment.new(tokens_lists[0])
        if @assignment.count_target.zero?
          @errors << 'Assignment must have left-hand value(s)'
        end
        if @assignment.count_value != 1
          @errors << 'Assignment must have only one right-hand value'
        end
      rescue BASICExpressionError => e
        @errors << e.message
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    lines += @assignment.dump unless @assignment.nil?

    lines
  end

  def execute_core(interpreter)
    l_values = @assignment.eval_target(interpreter)
    r_values = @assignment.eval_value(interpreter)
    r_value = r_values[0]

    l_values.each do |l_value|
      interpreter.set_value(l_value, r_value)
    end
  end

  def variables
    vars = []
    vars = @assignment.variables unless @assignment.nil?

    vars
  end
end

# LET
class LetStatement < AbstractLetStatement
  def self.lead_keywords
    [
      [KeywordToken.new('LET')]
    ]
  end

  def initialize(_, _)
    super
  end
end

# LET-less assignment
class LetLessStatement < AbstractLetStatement
  def self.lead_keywords
    [
      []
    ]
  end

  def initialize(_, _)
    super
  end
end

# LINE INPUT
class LineInputStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('LINE'), KeywordToken.new('INPUT')],
      [KeywordToken.new('LINPUT')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      input_items = split_tokens(tokens_lists[0], false)
      input_items = tokens_to_expressions(input_items)
      @file_tokens, input_items = extract_file_handle(input_items)
      @prompt, @input_items = extract_prompt(input_items)

      if !@input_items.empty? && @input_items[0].text_constant?
        @prompt = input_items[0]
        @input_items = @input_items[1..-1]
      end
    else
      @errors << 'Syntax error'
    end
  end

  include FileFunctions
  include InputFunctions

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :read)

    prompt = nil

    unless @prompt.nil?
      prompts = @prompt.evaluate(interpreter)
      prompt = prompts[0]
    end

    if fh.nil?
      values = input_values(fhr, interpreter, prompt, @input_items.size)
      fhr.implied_newline
    else
      values = fhr.line_input(interpreter)
    end

    name_value_pairs =
      zip(@input_items, values[0..@input_items.length])

    name_value_pairs.each do |hash|
      l_values = hash['name'].evaluate(interpreter)
      l_value = l_values[0]
      value = hash['value']
      interpreter.set_value(l_value, value)
    end
  end

  private

  def input_values(fhr, interpreter, prompt, count)
    values = []

    while values.size < count
      fhr.prompt(prompt)
      values += fhr.line_input(interpreter)

      prompt = nil
    end

    values
  end
end

# NEXT
class NextStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('NEXT')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    template1 = [[1, '>=']]
    template2 = []

    if check_template(tokens_lists, template1)
      # parse control variables
      @controls = []

      tokens_list = split_on_group_separators(tokens_lists[0])
      tokens_list.each do |tokens|
        if tokens.empty?
          @controls << EmptyToken.new
        elsif tokens.size == 1 && tokens[0].variable?
          control = VariableName.new(tokens[0])
          @controls << control
        else
          @errors << "Invalid control variable #{tokens[0]}"
        end
      end
    elsif check_template(tokens_lists, template2)
      @controls = [EmptyToken.new]
    else
      @errors << 'Syntax error'
    end
  end

  def has_control(control)
    @controls.include?(control)
  end

  def dump
    vars = []

    if !@controls.nil?
      @controls.each do |control|
        vars << control.dump unless control.empty?
      end
    end

    vars
  end

  def execute_core(interpreter)
    max = @controls.size

    # for each control, until we find one that is not terminated
    found_unterminated = false
    index = 0

    while !found_unterminated && index < max
      if @controls[index].empty?
        control = interpreter.top_fornext
        fornext_control = interpreter.retrieve_fornext(control)
      else
        fornext_control = interpreter.retrieve_fornext(@controls[index])
      end
      # check control variable value
      # if matches end value, stop here
      terminated = fornext_control.terminated?(interpreter)
      io = interpreter.trace_out
      s = ' terminated:' + terminated.to_s
      io.trace_output(s)

      if terminated
        interpreter.unlock_variable(@controls[index])
        interpreter.exit_fornext
      else
        # set next line from top item
        interpreter.next_line_index = fornext_control.loop_start_index
        # change control variable value
        fornext_control.bump_control(interpreter)

        found_unterminated = true
      end

      index += 1
    end
  end
end

# ON ERROR GOTO
class OnErrorStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ON'), KeywordToken.new('ERROR'), KeywordToken.new('GOTO')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    @destinations = nil

    template = [[1]]

    if check_template(tokens_lists, template)
      destinations = tokens_lists[0]
      line_nums = split_tokens(destinations, false)
      destinations = line_nums[0]
      destination = destinations[0]

      if destination.numeric_constant?
        @destination = LineNumber.new(destination)
      else
        @errors << "Invalid line number #{destination}"
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = [@destination.dump]
  end

  def program_check(program, console_io, line_number_index)
    retval = true

    unless @destinations.nil?
      unless program.line_number?(@destination)
        console_io.print_line(
          "Line number #{@destination} not found in line #{line_number_index}"
        )
        retval = false
      end
    end

    retval
  end

  def execute_core(interpreter)
    interpreter.seterrorgoto(@destination)
  end

  def renumber(renumber_map)
    @destination = renumber_map[@destination]
  end
end

# ON GOTO/ON GOSUB
class OnStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ON')]
    ]
  end

  def self.extra_keywords
    %w(GOTO THEN GOSUB)
  end

  def initialize(keywords, tokens_lists)
    super

    @destinations = nil
    @expression = nil

    template1 = [[1, '>='], 'GOTO', [1, '>=']]
    template2 = [[1, '>='], 'THEN', [1, '>=']]
    template3 = [[1, '>='], 'GOSUB', [1, '>=']]

    if check_template(tokens_lists, template1) ||
       check_template(tokens_lists, template2) ||
       check_template(tokens_lists, template3)
      expression = tokens_lists[0]

      begin
        @expression = ValueScalarExpression.new(expression)
      rescue BASICExpressionError => e
        @errors << e.message
      end

      @gosub = tokens_lists[1] == 'GOSUB'

      destinations = tokens_lists[2]
      line_nums = split_tokens(destinations, false)
      @destinations = []

      line_nums.each do |line_num|
        if line_num.size == 1
          destination = line_num[0]
          if destination.numeric_constant?
            line_number = LineNumber.new(destination)
            @destinations << line_number
          else
            @errors << "Invalid line number #{destination}"
          end
        else
          @errors << "Invalid line specification #{line_num}"
        end
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    lines += @expression.dump
    @destinations.each { |destination| lines << destination.dump }
    lines
  end

  def program_check(program, console_io, line_number_index)
    retval = true

    unless @destinations.nil?
      @destinations.each do |destination|
        unless program.line_number?(destination)
          console_io.print_line(
            "Line number #{destination} not found in line #{line_number_index}"
          )
          retval = false
        end
      end
    end

    retval
  end

  def execute_core(interpreter)
    values = @expression.evaluate(interpreter)

    raise(BASICExpressionError, 'Expecting one value') unless values.size == 1

    value = values[0]

    raise(BASICExpressionError, 'Invalid value') unless value.numeric_constant?

    io = interpreter.trace_out
    io.trace_output(' ' + @expression.to_s + ' = ' + value.to_s)
    index = value.to_i

    raise(BASICRuntimeError, 'Index out of range') if
      index < 1 || index > @destinations.size

    # get destination in list
    line_number = @destinations[index - 1]
    index = interpreter.statement_start_index(line_number, 0)

    raise(BASICRuntimeError, 'Line number not found') if index.nil?

    interpreter.push_return(interpreter.next_line_index) if @gosub
    
    destination = LineNumberIndex.new(line_number, 0, index)
    interpreter.next_line_index = destination
  end

  def renumber(renumber_map)
    new_destinations = []

    @destinations.each do |destination|
      new_destinations << renumber_map[destination]
    end

    @destinations = new_destinations
  end

  def variables
    vars = []
    vars += @expression.variables unless @expression.nil?

    vars
  end
end

# OPEN
class OpenStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('OPEN')]
    ]
  end

  def self.extra_keywords
    %w(FOR INPUT OUTPUT APPEND AS FILE)
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template_input_as = [[1, '>='], 'FOR', 'INPUT', 'AS', [1, '>=']]
    template_input_as_file =
      [[1, '>='], 'FOR', 'INPUT', 'AS', 'FILE', [1, '>=']]

    template_output_as = [[1, '>='], 'FOR', 'OUTPUT', 'AS', [1, '>=']]
    template_output_as_file =
      [[1, '>='], 'FOR', 'OUTPUT', 'AS', 'FILE', [1, '>=']]

    template_append_as = [[1, '>='], 'FOR', 'APPEND', 'AS', [1, '>=']]
    template_append_as_file =
      [[1, '>='], 'FOR', 'APPEND', 'AS', 'FILE', [1, '>=']]

    if check_template(tokens_lists, template_input_as) ||
       check_template(tokens_lists, template_input_as_file)
      @filename_expression = ValueScalarExpression.new(tokens_lists[0])
      @filenum_expression = ValueScalarExpression.new(tokens_lists[-1])
      @mode = :read
    elsif check_template(tokens_lists, template_output_as) ||
          check_template(tokens_lists, template_output_as_file)
      @filename_expression = ValueScalarExpression.new(tokens_lists[0])
      @filenum_expression = ValueScalarExpression.new(tokens_lists[-1])
      @mode = :print
    elsif check_template(tokens_lists, template_append_as) ||
          check_template(tokens_lists, template_append_as_file)
      @filename_expression = ValueScalarExpression.new(tokens_lists[0])
      @filenum_expression = ValueScalarExpression.new(tokens_lists[-1])
      @mode = :append
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    lines += @filename_expression.dump unless @filename_expression.nil?
    lines += @filenum_expression.dump unless @filenum_expression.nil?

    lines
  end

  def execute_core(interpreter)
    filenames = @filename_expression.evaluate(interpreter)
    filename = filenames[0]
    fhs = @filenum_expression.evaluate(interpreter)
    fh = fhs[0]

    case fh.class.to_s
    when 'Fixnum'
      fh = FileHandle.new(fh)
    when 'NumericConstant'
      fh = FileHandle.new(fh.to_i)
    when 'IntegerConstant'
      fh = FileHandle.new(fh.to_i)
    when 'FileHandle'
      fh = fhs[0]
    else
      raise(BASICRuntimeError, "Invalid file number #{fh.class}:#{fh}")
    end

    interpreter.open_file(filename, fh, @mode)
  end
end

# OPTION
class OptionStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('OPTION')]
    ]
  end

  def self.extra_keywords
    %w(BASE PROVENANCE TRACE)
  end

  def initialize(keywords, tokens_lists)
    super

    # omit HEADING and TIMING as they are not used in the interpreter
    # omit PRETTY_MULTILINE too
    template = [['BASE', 'PROVENANCE', 'TRACE'], [1, '>=']]

    if check_template(tokens_lists, template)
      @key = tokens_lists[0].to_s.downcase
      expression_tokens = split_tokens(tokens_lists[1], true)
      @expression = ValueScalarExpression.new(expression_tokens[0])
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    lines += @expression.dump unless @expression.nil?

    lines
  end

  def execute(interpreter)
    console_io = interpreter.console_io

    values = @expression.evaluate(interpreter)
    value0 = values[0]

    interpreter.set_action(@key, value0.to_v)
  end

  def variables
    vars = []
    vars += @expression.variables unless @expression.nil?

    vars
  end
end

# common for PRINT, ARR PRINT, MAT PRINT
class AbstractPrintStatement < AbstractStatement
  def initialize(keywords, tokens_lists, final_carriage)
    super(keywords, tokens_lists)

    @final = final_carriage
  end

  def dump
    lines = []

    unless @file_tokens.nil?
      lines << 'FILE'
      lines += @file_tokens.dump
    end

    lines << 'ITEMS'
    @print_items.each { |item| lines += item.dump } unless @print_items.nil?
    lines
  end

  def variables
    vars = []
    vars += @file_tokens.variables unless @file_tokens.nil?
    @print_items.each { |item| vars += item.variables } unless @print_items.nil?

    vars
  end

  include FileFunctions
end

# PRINT
class PrintStatement < AbstractPrintStatement
  def self.lead_keywords
    [
      [KeywordToken.new('PRINT')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super(keywords, tokens_lists, CarriageControl.new('NL'))

    extract_modifiers(tokens_lists)

    template1 = []
    template2 = [[1, '>=']]

    if check_template(tokens_lists, template1)
      @print_items = tokens_to_expressions([])
    elsif check_template(tokens_lists, template2)
      tokens_lists = split_tokens(tokens_lists[0], true)
      print_items = tokens_to_expressions(tokens_lists)
      @file_tokens, @print_items = extract_file_handle(print_items)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    @print_items.each do |item|
      item.print(fhr, interpreter)
    end
  end

  private

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(print_items, tokens_list)
      elsif tokens_list.separator?
        print_items << CarriageControl.new(tokens_list.to_s)
      end
    end

    add_implied_items(print_items, @final)

    print_items
  end

  def add_expression(print_items, tokens)
    if !print_items.empty? &&
       print_items[-1].class.to_s == 'ValueScalarExpression'
      print_items << CarriageControl.new('')
    end
    begin
      print_items << ValueScalarExpression.new(tokens)
    rescue BASICExpressionError
      line_text = tokens.map(&:to_s).join
      @errors << 'Syntax error: "' + line_text + '" is not a value or operator'
    end
  end
end

# PRINT USING
class PrintUsingStatement < AbstractPrintStatement
  def self.lead_keywords
    [
      [KeywordToken.new('PRINT'), KeywordToken.new('USING')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super(keywords, tokens_lists, CarriageControl.new('NL'))

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      @file_tokens = nil
      @print_items = tokens_to_expressions(tokens_lists)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    format_spec, print_items = extract_format(@print_items, interpreter)

    raise(BASICRuntimeError, 'No print format') if format_spec.nil?

    # split format
    formats = split_format(format_spec)
    fhr = interpreter.console_io

    formats.each do |format|
      constant = nil

      if format.wants_item
        item = print_items.shift

        item = print_items.shift while
          !print_items.empty? &&
          item.carriage_control?

        raise(BASICRuntimeError, 'Too few print items for format') if
          item.nil?

        constants = item.evaluate(interpreter)
        constant = constants[0]
      end

      text = format.format(constant)
      text.print(fhr)
    end

    until print_items.empty?
      item = print_items.shift
      item.print(fhr, interpreter) unless item.nil?
    end
  end

  private

  def extract_format(print_items, interpreter)
    print_items = print_items.clone
    format = nil

    unless print_items.empty? ||
           print_items[0].class.to_s != 'ValueScalarExpression'

      value = first_item(print_items, interpreter)

      if value.text_constant?
        format = value
        print_items.shift

        print_items.shift if
          !print_items.empty? &&
          print_items[0].carriage_control?
      end
    end

    [format, print_items]
  end

  def first_item(print_items, interpreter)
    first_list = print_items[0]
    values = first_list.evaluate(interpreter)

    values[0]
  end

  def split_format(format)
    format_text = format.to_v
    tokenbuilders = [
      ConstantFormatTokenBuilder.new,
      PaddedStringFormatTokenBuilder.new,
      PlainStringFormatTokenBuilder.new,
      CharFormatTokenBuilder.new,
      NumericFormatTokenBuilder.new
    ]
    tokenizer = Tokenizer.new(tokenbuilders, nil)
    tokenizer.tokenize(format_text)
  end

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(print_items, tokens_list)
      elsif tokens_list.separator?
        print_items << CarriageControl.new(tokens_list.to_s)
      end
    end

    add_implied_items(print_items, @final)

    print_items
  end

  def add_expression(print_items, tokens)
    if !print_items.empty? &&
       print_items[-1].class.to_s == 'ValueScalarExpression'
      print_items << CarriageControl.new('')
    end

    print_items << ValueScalarExpression.new(tokens)

  rescue BASICExpressionError
    line_text = tokens.map(&:to_s).join
    @errors << 'Syntax error: "' + line_text + '" is not a value or operator'
  end
end

# RANDOMIZE
class RandomizeStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('RANDOMIZE')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def dump
    ['']
  end

  def execute_core(interpreter)
    interpreter.new_random
  end
end

# common for READ, ARR READ, MAT READ
class AbstractReadStatement < AbstractStatement
  def initialize(keywords, tokens_lists)
    super
  end

  def dump
    lines = []
    @read_items.each { |item| lines += item.dump } unless @read_items.nil?

    lines
  end

  def variables
    vars = []
    vars += @file_tokens.variables unless @file_tokens.nil?
    @read_items.each { |item| vars += item.variables } unless @read_items.nil?

    vars
  end

  include FileFunctions
end

# READ
class ReadStatement < AbstractReadStatement
  def self.lead_keywords
    [
      [KeywordToken.new('READ')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      read_items = split_tokens(tokens_lists[0], false)
      read_items = tokens_to_expressions(read_items)
      @file_tokens, @read_items = extract_file_handle(read_items)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    ds = interpreter.get_data_store(fh)

    @read_items.each do |item|
      targets = item.evaluate(interpreter)
      targets.each do |target|
        value = ds.read
        interpreter.set_value(target, value)
      end
    end
  end

  private

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(print_items, tokens_list)
      end
    end

    print_items
  end

  def add_expression(print_items, tokens)
    if tokens[0].operator? && tokens[0].to_s == '#'
      print_items << ValueScalarExpression.new(tokens)
    else
      print_items << TargetExpression.new(tokens, ScalarReference)
    end

  rescue BASICExpressionError
    line_text = tokens.map(&:to_s).join
    @errors << 'Syntax error: "' + line_text + '" is not a value or operator'
  end
end

# RESTORE
class RestoreStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('RESTORE')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def dump
    ['']
  end

  def execute_core(interpreter)
    ds = interpreter.get_data_store(nil)
    ds.reset
  end
end

# RESUME
class ResumeStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('RESUME')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template_0 = []
    template_1 = [[1, '>=']]

    target = nil
    if check_template(tokens_lists, template_0)
      target = nil
    elsif check_template(tokens_lists, template_1)
      target = tokens_lists[0][0]
    else
      @errors << 'Syntax error'
    end

    @target = nil
    if !target.nil?
      begin
        @target = LineNumber.new(target)
      rescue BASICSyntaxError
        @errors << 'Invalid target'
      end
    end
  end

  def dump
    ['']
  end

  def execute_core(interpreter)
    ds = interpreter.resume(@target)
  end
end

# RETURN
class ReturnStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('RETURN')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def dump
    ['']
  end

  def execute_core(interpreter)
    interpreter.next_line_index = interpreter.pop_return
  end
end

# SLEEP
class SleepStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('SLEEP')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template_0 = []
    template_1 = [[1, '>=']]

    if check_template(tokens_lists, template_0)
      token_lists = [[NumericConstantToken.new('5')]]
    elsif check_template(tokens_lists, template_1)
      token_lists = split_tokens(tokens_lists[0], false)
    else
      @errors << 'Syntax error'
    end

    @errors << 'Too many values' if token_lists.size > 1

    @expression = ValueScalarExpression.new(token_lists[0])
  end

  def dump
    @expression.dump
  end

  def execute_core(interpreter)
    values = @expression.evaluate(interpreter)
    value = values[0]
    sleep(value.to_v)
  end
end

# STOP
class StopStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('STOP')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def dump
    ['']
  end

  def execute_core(interpreter)
    io = interpreter.console_io
    io.newline_when_needed
    interpreter.stop
  end
end

# common for WRITE, ARR WRITE, MAT WRITE
class AbstractWriteStatement < AbstractStatement
  def initialize(keywords, tokens_lists, final_carriage)
    super(keywords, tokens_lists)

    @final = final_carriage
  end

  def dump
    lines = []
    @print_items.each { |item| lines += item.dump } unless @print_items.nil?
    lines
  end

  def variables
    vars = []
    vars += @file_tokens.variables unless @file_tokens.nil?
    @print_items.each { |item| vars += item.variables } unless @print_items.nil?

    vars
  end

  include FileFunctions
end

# WRITE
class WriteStatement < AbstractWriteStatement
  def self.lead_keywords
    [
      [KeywordToken.new('WRITE')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super(keywords, tokens_lists, CarriageControl.new('NL'))

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      print_items = tokens_to_expressions(tokens_lists)
      @file_tokens, @print_items = extract_file_handle(print_items)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    @print_items.each do |item|
      item.write(fhr, interpreter)
    end
  end

  private

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(print_items, tokens_list)
      elsif tokens_list.separator?
        print_items << CarriageControl.new(tokens_list.to_s)
      end
    end

    add_implied_items(print_items, @final)

    print_items
  end

  def add_expression(print_items, tokens)
    if !print_items.empty? &&
       print_items[-1].class.to_s == 'ValueScalarExpression'
      print_items << CarriageControl.new('')
    end

    print_items << ValueScalarExpression.new(tokens)

  rescue BASICExpressionError
    line_text = tokens.map(&:to_s).join
    @errors << 'Syntax error: "' + line_text + '" is not a value or operator'
  end
end

# ARR PRINT
class ArrPrintStatement < AbstractPrintStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR'), KeywordToken.new('PRINT')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super(keywords, tokens_lists, CarriageControl.new(','))

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      print_items = tokens_to_expressions(tokens_lists)
      @file_tokens, @print_items = extract_file_handle(print_items)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    i = 0
    @print_items.each do |item|
      if item.printable?
        carriage = CarriageControl.new('')
        carriage = @print_items[i + 1] if
          i < @print_items.size &&
          !@print_items[i + 1].printable?
        item.print(fhr, interpreter, carriage)
      end
      i += 1
    end
  end

  private

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        print_items << ValueArrayExpression.new(tokens_list)
      elsif tokens_list.separator?
        print_items << CarriageControl.new(tokens_list)
      end
    end

    add_implied_items(print_items, @final)

    print_items
  end
end

# ARR READ
class ArrReadStatement < AbstractReadStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR'), KeywordToken.new('READ')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      read_items = split_tokens(tokens_lists[0], false)
      read_items = tokens_to_expressions(read_items)
      @file_tokens, @read_items = extract_file_handle(read_items)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    ds = interpreter.get_data_store(fh)

    @read_items.each do |item|
      targets = item.evaluate(interpreter)
      targets.each do |target|
        interpreter.set_dimensions(target, target.dimensions) if
          target.dimensions?
        read_values(target.name, interpreter, ds)
      end
    end
  end

  private

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(print_items, tokens_list)
      end
    end

    print_items
  end

  def add_expression(print_items, tokens)
    if tokens[0].operator? && tokens[0].to_s == '#'
      print_items << ValueScalarExpression.new(tokens)
    else
      print_items << TargetExpression.new(tokens, ArrayReference)
    end

  rescue BASICExpressionError
    line_text = tokens.map(&:to_s).join
    @errors << 'Syntax error: "' + line_text + '" is not a value or operator'
  end

  def read_values(name, interpreter, ds)
    dims = interpreter.get_dimensions(name)

    case dims.size
    when 1
      read_array(name, dims, interpreter, ds)
    else
      raise(BASICRuntimeError, 'Dimensions for ARR READ must be 1')
    end
  end

  def read_array(name, dims, interpreter, ds)
    values = {}

    base = interpreter.base
    (base..dims[0].to_i).each do |col|
      coord = make_coord(col)
      values[coord] = ds.read
    end

    interpreter.set_values(name, values)
  end
end

# ARR WRITE
class ArrWriteStatement < AbstractWriteStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR'), KeywordToken.new('WRITE')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super(keywords, tokens_lists, CarriageControl.new(','))

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      print_items = tokens_to_expressions(tokens_lists)
      @file_tokens, @print_items = extract_file_handle(print_items)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    i = 0

    @print_items.each do |item|
      if item.printable?
        carriage = CarriageControl.new('')
        carriage = @print_items[i + 1] if
          i < @print_items.size &&
          !@print_items[i + 1].printable?
        item.write(fhr, interpreter, carriage)
      end

      i += 1
    end
  end

  private

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        print_items << ValueArrayExpression.new(tokens_list)
      elsif tokens_list.separator?
        print_items << CarriageControl.new(tokens_list)
      end
    end

    add_implied_items(print_items, @final)

    print_items
  end
end

# ARR assignment
class ArrLetStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[3, '>=']]

    if check_template(tokens_lists, template)
      begin
        @assignment = ArrayAssignment.new(tokens_lists[0])

        if @assignment.count_target.zero?
          @errors << 'Assignment must have left-hand value(s)'
        end

        if @assignment.count_value != 1
          @errors << 'Assignment must have only one right-hand value'
        end
      rescue BASICExpressionError => e
        @errors << e.message
        @assignment = @rest
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    lines += @assignment.dump unless @assignment.nil?

    lines
  end

  def execute_core(interpreter)
    r_value = first_value(interpreter)
    dims = r_value.dimensions
    values = r_value.values(interpreter)

    l_values = @assignment.eval_target(interpreter)

    l_values.each do |l_value|
      interpreter.set_dimensions(l_value, dims)
      interpreter.set_values(l_value.name, values)
    end
  end

  def variables
    vars = []
    vars = @assignment.variables unless @assignment.nil?

    vars
  end

  private

  def first_target(interpreter)
    l_values = @assignment.eval_target(interpreter)

    l_values[0]
  end

  def first_value(interpreter)
    r_values = @assignment.eval_value(interpreter)
    r_value = r_values[0]

    raise(BASICRuntimeError, 'Expected Array') if
      r_value.class.to_s != 'BASICArray'

    r_value
  end
end

# MAT PRINT
class MatPrintStatement < AbstractPrintStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT'), KeywordToken.new('PRINT')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super(keywords, tokens_lists, CarriageControl.new(','))

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      print_items = tokens_to_expressions(tokens_lists)
      @file_tokens, @print_items = extract_file_handle(print_items)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    i = 0

    @print_items.each do |item|
      if item.printable?
        carriage = CarriageControl.new('')
        carriage = @print_items[i + 1] if
          i < @print_items.size &&
          !@print_items[i + 1].printable?
        item.print(fhr, interpreter, carriage)
      end

      i += 1
    end
  end

  private

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        print_items << ValueMatrixExpression.new(tokens_list)
      elsif tokens_list.separator?
        print_items << CarriageControl.new(tokens_list)
      end
    end

    add_implied_items(print_items, @final)

    print_items
  end
end

# MAT READ
class MatReadStatement < AbstractReadStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT'), KeywordToken.new('READ')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      read_items = split_tokens(tokens_lists[0], false)
      read_items = tokens_to_expressions(read_items)
      @file_tokens, @read_items = extract_file_handle(read_items)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    ds = interpreter.get_data_store(fh)

    @read_items.each do |item|
      targets = item.evaluate(interpreter)
      targets.each do |target|
        interpreter.set_dimensions(target, target.dimensions) if
          target.dimensions?
        read_values(target.name, interpreter, ds)
      end
    end
  end

  private

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(print_items, tokens_list)
      end
    end

    print_items
  end

  def add_expression(print_items, tokens)
    if tokens[0].operator? && tokens[0].to_s == '#'
      print_items << ValueScalarExpression.new(tokens)
    else
      print_items << TargetExpression.new(tokens, MatrixReference)
    end

  rescue BASICExpressionError
    line_text = tokens.map(&:to_s).join
    @errors << 'Syntax error: "' + line_text + '" is not a value or operator'
  end

  def read_values(name, interpreter, ds)
    dims = interpreter.get_dimensions(name)

    case dims.size
    when 1
      read_vector(name, dims, interpreter, ds)
    when 2
      read_matrix(name, dims, interpreter, ds)
    else
      raise(BASICRuntimeError, 'Dimensions for MAT READ must be 1 or 2')
    end
  end

  def read_vector(name, dims, interpreter, ds)
    values = {}

    (1..dims[0].to_i).each do |col|
      coord = make_coord(col)
      values[coord] = ds.read
    end

    interpreter.set_values(name, values)
  end

  def read_matrix(name, dims, interpreter, ds)
    values = {}

    (1..dims[0].to_i).each do |row|
      (1..dims[1].to_i).each do |col|
        coords = make_coords(row, col)
        values[coords] = ds.read
      end
    end

    interpreter.set_values(name, values)
  end
end

# MAT WRITE
class MatWriteStatement < AbstractWriteStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT'), KeywordToken.new('WRITE')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super(keywords, tokens_lists, CarriageControl.new(','))

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      print_items = tokens_to_expressions(tokens_lists)
      @file_tokens, @print_items = extract_file_handle(print_items)
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    i = 0
    @print_items.each do |item|
      if item.printable?
        carriage = CarriageControl.new('')
        carriage = @print_items[i + 1] if
          i < @print_items.size &&
          !@print_items[i + 1].printable?
        item.write(fhr, interpreter, carriage)
      end

      i += 1
    end
  end

  private

  def tokens_to_expressions(tokens_lists)
    print_items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        print_items << ValueMatrixExpression.new(tokens_list)
      elsif tokens_list.separator?
        print_items << CarriageControl.new(tokens_list)
      end
    end

    add_implied_items(print_items, @final)

    print_items
  end
end

# MAT assignment
class MatLetStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT')]
    ]
  end

  def initialize(keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[3, '>=']]

    if check_template(tokens_lists, template)
      begin
        @assignment = MatrixAssignment.new(tokens_lists[0])

        if @assignment.count_target.zero?
          @errors << 'Assignment must have left-hand value(s)'
        end

        if @assignment.count_value != 1
          @errors << 'Assignment must have only one right-hand value'
        end

      rescue BASICRuntimeError => e
        @errors << e.message
        @assignment = @rest
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []
    lines += @assignment.dump unless @assignment.nil?

    lines
  end

  def execute_core(interpreter)
    l_values = @assignment.eval_target(interpreter)
    l_value = l_values[0]
    l_dims = interpreter.get_dimensions(l_value.name)

    interpreter.set_default_args('CON', l_dims)
    interpreter.set_default_args('IDN', l_dims)
    interpreter.set_default_args('ZER', l_dims)

    # evaluate, use default args if needed
    r_values = @assignment.eval_value(interpreter)
    r_value = r_values[0]

    raise(BASICRuntimeError, 'Expected Matrix') if
      r_value.class.to_s != 'Matrix'

    interpreter.set_default_args('CON', nil)
    interpreter.set_default_args('IDN', nil)
    interpreter.set_default_args('ZER', nil)

    r_dims = r_value.dimensions
    values = r_value.values_1 if r_dims.size == 1
    values = r_value.values_2 if r_dims.size == 2

    l_values.each do |l_value|
      interpreter.set_dimensions(l_value, r_dims)
      interpreter.set_values(l_value.name, values)
    end
  end

  def variables
    vars = []
    vars = @assignment.variables unless @assignment.nil?

    vars
  end
end
