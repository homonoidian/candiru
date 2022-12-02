# TODO: a lot of stuff: variadic functions, structs by value,
# unions, strings, chars, ...
#
# ... and reducing strain on the Crystal compiler

# Note: there is a lot of type vodoo going on for all of
# this to work. Some casts are going to be necessary despite
# all this, unfortunately.
#
# Beware.

require "compiler/crystal/ffi"

# Candiru "are known for an alleged tendency to invade and
# parasitise the human urethra".
module Candiru
  include Crystal

  # Non-generic supertype for the generic `ValueClass`.
  module IValueClassType
    # Returns the FFI type corresponding to this value class.
    #
    # ```
    # Int32.to_ffi # FFI::Type.sint32
    # ```
    abstract def to_ffi : FFI::Type

    # Performs the necessary type sorcery to create a `FieldValue(T)`
    # from a void *pointer* and the corresponding typed *field*.
    abstract def adopt_as_field_value(field : ITypedField, pointer : Void*)

    # Casts *pointer*, a return value hole from FFI, to this
    # type, and returns its value.
    abstract def from_ffi_return_pointer(pointer : Void*)

    # Returns whether this value class matches *other* value.
    def matches?(other)
      false
    end
  end

  # Should be extended by objects that want to be Crystal-
  # facing FFI description objects (e.g. Int32, Float64).
  module ValueClass(T)
    include IValueClassType

    def adopt_as_field_value(field : ITypedField, pointer : Void*) : FieldValue(T)
      # Just... don't ask me, please. I don't know.
      FieldValue(T).new(field.as(TypedField(T)), pointer.as(T*).value)
    end

    def from_ffi_return_pointer(pointer : Void*)
      pointer.as(T*).value
    end

    def matches?(other : T)
      true
    end
  end

  # Non-generic supertype for the generic `ValueInstance`.
  module IValueInstanceType
    # Returns an FFI argument pointer for this value instance.
    abstract def to_ffi_argument_pointer : Void*
  end

  # Should be included by objects that want to be Crystal-
  # facing FFI input/output objects.
  module ValueInstance(T)
    include IValueInstanceType

    # Returns raw content of this value instance.
    def raw : T
      self
    end
  end

  # Reopens number *subclass* and defines `ValueClass` and
  # `ValueInstance` methods.
  private macro number_ivalue(subclass, ffi_type_id)
    struct ::{{subclass.id}}
      include Candiru::ValueInstance(self)
      extend Candiru::ValueClass(self)

      def to_ffi_argument_pointer : Void*
        Pointer(self).malloc(1, self).as(Void*)
      end

      def self.to_ffi : Candiru::FFI::Type
        Candiru::FFI::Type.{{ffi_type_id.id}}
      end
    end
  end

  number_ivalue(UInt8, uint8)
  number_ivalue(Int8, sint8)

  number_ivalue(UInt16, uint16)
  number_ivalue(Int16, sint16)

  number_ivalue(UInt32, uint32)
  number_ivalue(Int32, sint32)

  number_ivalue(UInt64, uint64)
  number_ivalue(Int64, sint64)

  number_ivalue(UInt64, uint64)
  number_ivalue(Int64, sint64)

  number_ivalue(Float32, float)
  number_ivalue(Float64, double)

  struct ::Nil
    include Candiru::ValueInstance(self)
    extend Candiru::ValueClass(self)

    def to_ffi_argument_pointer : Void*
      Pointer(Void*).null.as(Void*)
    end

    def self.to_ffi : Candiru::FFI::Type
      Candiru::FFI::Type.pointer # nullptr
    end
  end

  # Non-generic supertype of generic `TypedField`.
  module ITypedField
  end

  # A struct field holding a Crystal type *T*.
  #
  # *T* must implement `.to_ffi` which must return the `FFI::Type`
  # corresponding to *T*.
  struct TypedField(T)
    include ITypedField

    # Returns the FFI type corresponding to this typed field.
    getter ffi_type : FFI::Type

    # Returns the Crystal type (*T*) corresponding to this
    # typed field.
    getter type = T

    # Returns the offset of this typed field in the parent
    # struct.
    getter offset : UInt64

    # In case this typed field is a pointer to another struct,
    # or a struct itself, returns the scaffolding of that struct.
    getter? scaffolding : StructScaffolding?

    def initialize(@ffi_type, @offset, @scaffolding = nil)
    end

    # Returns whether this typed field matches the given *value*.
    def matches?(value : T)
      true
    end

    # :ditto:
    def matches?(value : StructInstance)
      value.scaffolding == scaffolding?
    end

    # :ditto:
    def matches?(value)
      false
    end

    def to_s(io)
      io << T << ", " << offset << " in, " << ffi_type.to_unsafe.value.@type
    end
  end

  # Non-generic supertype of generic `TypedField`.
  module IFieldValue
  end

  # A `TypedField(T)` grouped with the appropriately typed value.
  record FieldValue(T), field : TypedField(T), value : ValueInstance(T) do
    include IFieldValue

    # Converts the field value to a struct instance. Field value
    # must be a valid pointer address (`UInt64`). Typed field
    # must have a scaffolding attached.
    #
    # Returns nil if any of those conditions are false.
    def as_struct_instance?
      return unless scaffolding = field.scaffolding?
      return unless T.is_a?(UInt64.class)

      address = value.raw.unsafe_as(UInt64)

      scaffolding.new(Pointer(Void).new(address))
    end

    # Writes value at *struct_pointer* plus the required field
    # offset, and returns the resulting pointer to value.
    def write(struct_pointer) : Pointer(T)
      pointer = Pointer(T).new(struct_pointer.address + field.offset)
      pointer.value = value.raw
      pointer
    end

    def to_s(io)
      io << "<#{value} :: #{field}>"
    end
  end

  # Struct scaffolding helps to describe the scaffolding of
  # structs.
  #
  # This implementation treats structs as arrays with (possibly)
  # different type for each element.
  #
  # ```
  # point = StructScaffolding[Int32, Int32]
  #
  # instance = point.new do |b|
  #   b << 123
  #   b << 456
  # end
  #
  # instance.pointer # Pointer(Void)
  # ```
  class StructScaffolding
    include ValueClass(UInt64)

    # Returns the array of typed fields in this struct scaffolding.
    getter fields : Array(ITypedField)

    # Initializes an empty struct scaffolding.
    def initialize
      @size = 0u64
      @alignment = 0u64
      @padded_size = 0u64
      @fields = [] of ITypedField
    end

    # Redirected to `fields`.
    delegate :[], :each, :size, to: fields

    # https://github.com/jnr/jnr-ffi/blob/7cecfcf8358b49ab5505cfe6c426f7497e639513/src/main/java/jnr/ffi/StructLayout.java#L99
    private def align(offset, alignment)
      (offset + alignment - 1) & ~(alignment - 1)
    end

    # https://github.com/jnr/jnr-ffi/blob/7cecfcf8358b49ab5505cfe6c426f7497e639513/src/main/java/jnr/ffi/StructLayout.java#L104
    #
    # Aligns and appends a struct field of the given *size*
    # and *align*ment. Returns the field's offset in struct.
    private def append(size, align) : UInt64
      offset = align(@size, align)
      @size = Math.max(@size, offset + size)
      @alignment = Math.max(@alignment, align)
      @padded_size = align(@size, @alignment)
      offset
    end

    # Extracts size and alignment information from *ffi_type*,
    # and calls `append`. Returns the field's offset in struct.
    private def append(ffi_type : FFI::Type) : UInt64
      append(
        ffi_type.to_unsafe.value.@size.to_u64,
        ffi_type.to_unsafe.value.@alignment.to_u64
      )
    end

    # Returns the padded size of this struct, in bytes.
    def bytesize
      @padded_size
    end

    # Appends a struct field of the given *type*.
    def <<(type : T.class) forall T
      ffi_type = T.to_ffi
      offset = append(ffi_type)
      fields << TypedField(T).new(ffi_type, offset)
    end

    # Appends a **pointer** to another struct (could be itself,
    # e.g. in a linked list), as described by *scaffolding*.
    def <<(scaffolding : StructScaffolding)
      ffi_type = FFI::Type.pointer
      offset = append(ffi_type)
      fields << TypedField(UInt64).new(ffi_type, offset, scaffolding)
    end

    # Yields a `StructBuilder` which facilitates the creation
    # of an instance of this struct. Returns the resulting
    # struct instance.
    def new : StructInstance
      builder = StructBuilder.new(self)
      yield builder
      builder.malloc
    end

    # Blockless `new`.
    def new
      new { }
    end

    # Makes a struct instance from *pointer*. Unsafe: does not
    # verify whether the contents of *pointer* are valid for
    # use under this struct scaffolding.
    def new(pointer : Void*)
      StructInstance.new(self, pointer)
    end

    def to_ffi : FFI::Type
      FFI::Type.pointer
    end

    def from_ffi_return_pointer(pointer : Void*)
      StructInstance.new(self, Pointer(Void).new(pointer.as(UInt64*).value))
    end

    def matches?(other : StructInstance)
      self == other.scaffolding
    end

    # A shorthand for initializing struct scaffolding.
    #
    # ```
    # StructScaffolding[Int64, Int64]
    #
    # # Is the same as writing:
    #
    # scaffolding = StructScaffolding.new
    # scaffolding << Int64
    # scaffolding << Int64
    # ```
    macro [](*types)
    %scaffolding = Candiru::StructScaffolding.new
    {% for type in types %}
      %scaffolding << {{type}}
    {% end %}
    %scaffolding
  end
  end

  # Represents a live struct instance, pointed to by `pointer`
  # and described by `scaffolding`.
  #
  # ```
  # point_struct = StructScaffolding[Int32, Int32]
  # point = point_struct.new { |s| s << 12; s << 34 }
  #
  # # point : StructInstance
  #
  # puts point.sum(&.value.raw) # 46
  # ```
  record StructInstance, scaffolding : StructScaffolding, pointer : Pointer(Void) do
    include Indexable(IValueInstanceType)
    include ValueInstance(UInt64)
    extend ValueClass(UInt64)

    def unsafe_fetch(index : Int)
      return if pointer.null?
      field = scaffolding.fields[index]
      field_pointer = Pointer(Void).new(pointer.address + field.offset)
      field_value = field.type.adopt_as_field_value(field, field_pointer)
      (field_value.as_struct_instance? || field_value.value).as(IValueInstanceType)
    end

    def size
      scaffolding.size
    end

    def raw : UInt64
      pointer.address
    end

    def to_ffi_argument_pointer : Void*
      Pointer(Void*).malloc(1, pointer).as(Void*)
    end

    def self.to_ffi : FFI::Type
      FFI::Type.pointer
    end

    def to_s(io)
      io << "<struct@#{pointer.address}>"
    end
  end

  # Helps to construct and allocate a `StructInstance` based
  # on its `StructScaffolding`.
  #
  # Makes sure the amount of struct fields is right, their
  # type is right, etc.
  struct StructBuilder
    def initialize(@scaffolding : StructScaffolding)
      @values = [] of IFieldValue
    end

    # Appends a field with *value*.
    def <<(value : T) forall T
      raise "scaffolding count mismatch" unless @values.size < @scaffolding.size
      raise "scaffolding type mismatch" unless (field = @scaffolding.fields[@values.size]).matches?(value)

      @values << FieldValue(T).new(field.as(TypedField(T)), value)
    end

    # Appends a field with **pointer** to *value*.
    def <<(value : StructInstance)
      self << value.pointer.address
    end

    # Allocates memory for an instance, writes field  values
    # there, and returns the resulting `StructInstance`.
    def malloc
      raise "scaffolding count mismatch" unless @values.size == @scaffolding.size

      base_pointer = Pointer(Void).malloc(@scaffolding.size)

      @values.each do |value|
        value.write(base_pointer)
      end

      StructInstance.new(@scaffolding, base_pointer)
    end
  end

  # Helps call C functions with `IValue`s as arguments.
  #
  # ```
  # point_new_handle = loader.find_symbol("Point_New")
  # point_add_handle = loader.find_symbol("Point_Add")
  # point_see_handle = loader.find_symbol("Point_See")
  # point_free_handle = loader.find_symbol("Point_Free")
  #
  # point_struct = StructScaffold[Float64, Float64]
  #
  # point_new = Fn.new(point_new_handle, takes: [Float64, Float64], returns: point_struct)
  # point_add = Fn.new(point_add_handle, takes: [point_struct, point_struct], returns: point_struct)
  # point_see = Fn.new(point_see_handle, takes: [point_struct])
  # point_free = Fn.new(point_free_handle, takes: [point_struct])
  #
  # a = point_new_fn.call(100f64, 200f64)
  # b = point_new_fn.call(200f64, 300f64)
  #
  # # a : StructInstance
  # # b : StructInstance
  #
  # point_see_fn.call(a)
  # point_see_fn.call(b)
  #
  # c = point_add_fn.call(a, b)
  #
  # point_see_fn.call(c)
  #
  # point_free_fn.call(a)
  # point_free_fn.call(b)
  # point_free_fn.call(c)
  # ```
  class Fn
    @params : Array(IValueClassType)

    # Initializes a function given a dlopen *handle*, a type
    # list of *params* it takes (each is `IValueClassType`),
    # and the type of its *ret*urn value, also an
    # `IValueClassType`.
    def initialize(@handle : Void*, takes params = [] of IValueClassType, returns @ret : IValueClassType? = nil)
      @params = params.map(&.as(IValueClassType))

      if ret
        @cif = FFI::CallInterface.new(ret.to_ffi, params.map(&.to_ffi))
      else
        # TODO: nullptr vs void
        @cif = FFI::CallInterface.new(FFI::Type.void, params.map(&.to_ffi))
      end
    end

    def call(args : Array(IValueInstanceType) = [] of IValueInstanceType)
      raise "invalid argument count" unless @params.size == args.size

      @params.zip(args) do |param, arg|
        unless param.matches?(arg)
          raise "argument type mismatch"
        end
      end

      argptr = Pointer(Void*).malloc(args.size)

      args.each_with_index do |arg, index|
        argptr[index] = arg.to_ffi_argument_pointer
      end

      hole = Pointer(Void).malloc(1)
      @cif.call(@handle, argptr, hole)

      if ret = @ret
        ret.from_ffi_return_pointer(hole)
      end
    end

    def call(*args)
      call(args.to_a)
    end
  end
end
