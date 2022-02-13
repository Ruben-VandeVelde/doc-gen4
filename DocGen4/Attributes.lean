import Lean

namespace DocGen4

open Lean Meta

-- The following is probably completely overengineered but I love it
class ValueAttr (attrKind : Type → Type) where
  getValue {α : Type} [Inhabited α] [ToString α] : attrKind α → Environment → Name → Option String

structure ValueAttrWrapper (attrKind : Type → Type) [ValueAttr attrKind] where
  {α : Type}
  attr : attrKind α
  [str : ToString α]
  [inhab : Inhabited α]

def enumGetValue {α : Type} [Inhabited α] [ToString α] (attr : EnumAttributes α) (env : Environment) (decl : Name) : Option String := OptionM.run do
  let val ← EnumAttributes.getValue attr env decl
  some (toString val)

instance : ValueAttr EnumAttributes where
  getValue := enumGetValue

def parametricGetValue {α : Type} [Inhabited α] [ToString α] (attr : ParametricAttribute α) (env : Environment) (decl : Name) : Option String := OptionM.run do
  let val ← ParametricAttribute.getParam attr env decl
  some (attr.attr.name.toString ++ " " ++ toString val)

instance : ValueAttr ParametricAttribute where
  getValue := parametricGetValue

abbrev EnumAttrWrapper := ValueAttrWrapper EnumAttributes
abbrev ParametricAttrWrapper := ValueAttrWrapper ParametricAttribute

def tagAttributes : Array TagAttribute := #[IR.UnboxResult.unboxAttr, neverExtractAttr, Elab.Term.elabWithoutExpectedTypeAttr, SynthInstance.inferTCGoalsRLAttr, matchPatternAttr]

deriving instance Repr for Compiler.InlineAttributeKind
deriving instance Repr for Compiler.SpecializeAttributeKind

open Compiler in
instance : ToString InlineAttributeKind where
  toString kind :=
    match kind with
    | InlineAttributeKind.inline => "inline"
    | InlineAttributeKind.noinline => "noinline"
    | InlineAttributeKind.macroInline => "macroInline"
    | InlineAttributeKind.inlineIfReduce => "inlineIfReduce"

open Compiler in
instance : ToString SpecializeAttributeKind where
  toString kind :=
    match kind with
    | SpecializeAttributeKind.specialize => "specialize"
    | SpecializeAttributeKind.nospecialize => "nospecialize"

def enumAttributes : Array EnumAttrWrapper := #[⟨Compiler.inlineAttrs⟩, ⟨Compiler.specializeAttrs⟩]

instance : ToString ExternEntry where
  toString entry :=
    match entry with
    | ExternEntry.adhoc `all => ""
    | ExternEntry.adhoc backend => s!"{backend} adhoc"
    | ExternEntry.standard `all fn => fn
    | ExternEntry.standard backend fn => s!"{backend} {fn}"
    | ExternEntry.inline backend pattern => s!"{backend} inline {String.quote pattern}"
    -- TODO: The docs in the module dont specific how to render this
    | ExternEntry.foreign backend fn  => s!"{backend} foreign {fn}"

instance : ToString ExternAttrData where
  toString data := (data.arity?.map toString |>.getD "") ++ String.intercalate " " (data.entries.map toString)

def parametricAttributes : Array ParametricAttrWrapper := #[⟨externAttr⟩, ⟨Compiler.implementedByAttr⟩]

def getTags (decl : Name) : MetaM (Array String) := do
  let env ← getEnv
  pure $ tagAttributes.filter (TagAttribute.hasTag · env decl) |>.map (λ t => t.attr.name.toString)

def getValuesAux {α : Type} {attrKind : Type → Type} [va : ValueAttr attrKind] [Inhabited α] [ToString α] (decl : Name) (attr : attrKind α) : MetaM (Option String) := do
  let env ← getEnv
  pure $ va.getValue attr env decl

def getValues {attrKind : Type → Type} [ValueAttr attrKind] (decl : Name) (attrs : Array (ValueAttrWrapper attrKind)) : MetaM (Array String) := do
  let env ← getEnv
  let mut res := #[]
  for attr in attrs do
    if let some val ← @getValuesAux attr.α attrKind _ attr.inhab attr.str decl attr.attr then
      res := res.push val
  pure res

def getEnumValues (decl : Name) : MetaM (Array String) := getValues decl enumAttributes
def getParametricValues (decl : Name) : MetaM (Array String) := getValues decl parametricAttributes

def getDefaultInstance (decl : Name) (className : Name) : MetaM (Option String) := do
  let insts ← getDefaultInstances className
  for (inst, prio) in insts do
    if inst == decl then
      return some $ s!"defaultInstance {prio}"
  pure none

def hasSimp (decl : Name) : MetaM (Bool) := do
  let thms ← simpExtension.getTheorems
  pure $ thms.isLemma decl

def getAllAttributes (decl : Name) : MetaM (Array String) := do
  let tags ← getTags decl
  let enums ← getEnumValues decl
  let parametric ← getParametricValues decl
  let simp := if ←hasSimp decl then #["simp"] else #[]
  pure $ simp ++ tags ++ enums ++ parametric

end DocGen4