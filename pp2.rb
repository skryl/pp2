# Optional Arguments:
#
# Set the depth level for printing model associations
#   :assoc_levels => ##
# Ignore the format defined in the model and build a default formatter
#   :formatter => :default
# Min column width to display (hard cutoff)
#   :min_width => ##
# Max column width to display (hard cutoff)
#   :max_width => ##
# Max number of columns to display (hard cutoff)
#   :max_cols => ##
# Columns to ignore (columns that contain any of the substrings specified)
#   :select_cols => ['','','']
# Columns to include (columns that contain any of the substrings specified)
#   :reject_cols => ['','','']


module Kernel
  private
  def pp2(obj, opts = {})
    PP2.pp2(obj, opts)
    nil
  end
  module_function :pp2
end

class PP2

  # Default formatter constraints
  MAX_COLS = 10
  MAX_WIDTH = 20
  IGNORE_COLS = ['_id', '_on', '_at']

  def self.pp2(obj, opts = {})
    objs = to_a(obj)
    max_width = nil

    @header = true
    objs.each do |o|
      if o.class.ancestors.include?(ActiveRecord::Base)
        # Lock width of table cells to max cell width of first row for clean output
        new_opts = max_width ? opts.merge({ :min_width => max_width, :max_width => max_width}) : opts 
        status = pretty_print2(o, new_opts) 

        # Only lock width if no asscoations are printed in between
        max_width = status[:associations] ? nil : status[:max_width]
      else pp o
      end
    end
    @header = true

    nil
  end

private 

  #TODO: some error handling would be nice
  def self.pretty_print2(obj, opts = {})
    model_format = build_formatter(obj, opts)
    border_char, padding_char, header_sep, field_sep = '-', ' ', '-+-',  ' | '
    pad_width, max_field_width, data = 4, 0, {}

    # Apply filters
    fields = model_format[:fields].dup
    opts[:select_cols] = to_a(opts[:select_cols])
    opts[:reject_cols] = to_a(opts[:reject_cols])
    fields = fields.select {|field| opts[:select_cols].any? {|ic| field[:column].index(ic) } } unless opts[:select_cols].empty? 
    fields = fields.reject {|field| opts[:reject_cols].any? {|ic| field[:column].index(ic) } } unless opts[:reject_cols].empty? 
    fields = fields[0...opts[:max_cols]] if opts[:max_cols]

    # Extract data for each column to be displayed. Also, determine the width
    # of the widest field (header title or data field) to use as the default
    # field size.
    fields.each do |field|
      assoc_calls = field[:column].split('.')
      val = assoc_calls.inject(obj) {|o, method| o.send(method) }.to_s

      formatted_data = field[:format] ? (field[:format] % val) : val 
      field_width = field[:width] || [(field[:title] || field[:column]).length, formatted_data.length].max
      max_field_width = [max_field_width, field_width].max
      data[field[:column]] = formatted_data
    end 

    # override calculated field size if passed in
    min_width = opts[:min_width] ? [opts[:min_width], max_field_width].max : max_field_width 
    max_width = opts[:max_width] ? [opts[:max_width], min_width].min : min_width

    # indent padding
    indent_level = opts[:indent] || 0
    indent_pad = padding_char * (indent_level * pad_width)

    # build up header string
    if @header
      header_lines = fields.inject(['', '']) do |(header, separator), field|
        title = field[:title] || field[:column]
        header += (title[0...max_width].center(max_width, padding_char) + field_sep)
        separator += ((border_char * max_width) + header_sep)
        [header, separator]
      end 
      @header = false
    end
    
    # build up data string
    data = fields.inject('') do |data_line, field|
      data_line + data[field[:column]][0...max_width].center(max_width) + field_sep
    end

    # printing done here 
    data = field_sep + data
    data_border = (border_char * data.size) #footer

    if header_lines
      puts "\n\n"
      title =  obj.class.to_s.center(data.size, border_char)
      header = field_sep + header_lines[0]
      header_border = header_sep + header_lines[1]
    end

    [title, header, header_border, data, data_border].compact.each_with_index do |line, i|
      puts indent_pad + line[1..-2]
    end

    associations = model_format[:associations]
    assoc_levels = opts[:assoc_levels]
    traverse_assocs = associations && assoc_levels && assoc_levels != 0
    if traverse_assocs 
      associations.each do |assoc|
        assoc_obj = obj.send(assoc[:name])
        assoc_objs = to_a(assoc_obj)
        unless assoc_objs.empty?
          assoc_objs.sort! {|o1,o2| o1.send(assoc[:sort]) <=> o2.send(assoc[:sort]) }
          pp2(assoc_objs, opts.merge({ :assoc_levels => assoc_levels - 1, :indent => (opts[:indent] || 0) + 1 })) 
        end
      end
    end

    # return status
    { :associations => traverse_assocs, :max_width => max_width }
  end


  def self.build_formatter(obj, opts = {})
    klass = obj.class
    if klass.class_variable_defined?(:@@pp2_format)
      formatter = klass.send(:class_variable_get, :@@pp2_format) unless opts[:formatter] == :default
    end

    # default format generator
    unless formatter
      opts[:max_cols] ||= MAX_COLS
      opts[:max_width] ||= MAX_WIDTH
      opts[:ignore_cols] ||= IGNORE_COLS

      column_names = klass.column_names
      field_formats = column_names.inject([]) do |fields, cn|
        fields.push({ :column => cn })
      end
      formatter = {:fields => field_formats} 
    end
    formatter
  end


  def self.to_a(obj)
    obj.is_a?(Array) ? obj : [obj].compact
  end
  
      
end
