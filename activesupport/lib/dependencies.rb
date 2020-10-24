require File.dirname(__FILE__) + '/module_attribute_accessors'

module Dependencies
  extend self
  
  @@loaded = [ ]
  mattr_accessor :loaded

  @@mechanism = :load
  mattr_accessor :mechanism
  
  def depend_on(file_name, swallow_load_errors = false)
    if !loaded.include?(file_name)
      loaded << file_name

      begin
        require_or_load(file_name)
      rescue LoadError
        raise unless swallow_load_errors
      end
    end
  end

  def associate_with(file_name)
    depend_on(file_name, true)
  end

  def reload
    old_loaded = loaded
    clear
    
    old_loaded.each do |file_name| 
      begin
        silence_warnings { load("#{file_name}.rb") } unless loaded.include?(file_name)
      rescue LoadError
        # The association didn't reside in its own file, so we assume it was required by other means
      end
    end
  end
  
  def clear
    self.loaded = [ ]
  end
  
  private
    def require_or_load(file_name)
      mechanism == :load ? silence_warnings { load("#{file_name}.rb") } : require(file_name)
    end
end

Object.send(:define_method, :require_dependency)  { |file_name| Dependencies.depend_on(file_name) } unless Object.respond_to?(:require_dependency)
Object.send(:define_method, :require_association) { |file_name| Dependencies.associate_with(file_name) } unless Object.respond_to?(:require_association)

class Object
  class << self
    # Use const_missing to autoload associations so we don't have to
    # require_association when using single-table inheritance.
    unless respond_to?(:pre_dependency_const_missing)
      alias_method :pre_dependency_const_missing, :const_missing

      def const_missing(class_id)
        begin
          require_dependency(Inflector.underscore(Inflector.demodulize(class_id.to_s)))
          return Object.const_get(class_id) if Object.const_defined?(class_id)
        rescue LoadError
          pre_dependency_const_missing(class_id)
        end
      end
    end
  end
end