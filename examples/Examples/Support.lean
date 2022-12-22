import Lean
import Lean.Message
import Lean.Data.PersistentArray

syntax withPosition("book" "declaration" "{{{" ws ident ws "}}}" (command*) "stop" "book" "declaration") : command

elab_rules : command
  | `(book declaration {{{ $_name:ident }}} $decls* stop book declaration) => do
    for decl in decls do
      Lean.Elab.Command.elabCommand decl.raw

book declaration {{{ foo }}}
  def twentyFive : Nat := 25
stop book declaration

#check twentyFive

book declaration {{{ foo }}}
  namespace MyNamespaceIsGreat
  def twentyFive : Nat := 25
  end MyNamespaceIsGreat
stop book declaration

#check MyNamespaceIsGreat.twentyFive

syntax withPosition("bookExample" "{{{" ws ident ws "}}}" colGt term:10 colGt "===>" colGt term:10 "end bookExample") : command

elab_rules : command
  | `(bookExample {{{ $_name:ident }}} $x:term ===> $y:term end bookExample) =>
    open Lean.Elab.Command in
    open Lean.Elab.Term in
    open Lean.Meta in liftTermElabM <| withDeclName `bookExample do
      let x ← elabTerm x none
      let y ← elabTerm y none
      synthesizeSyntheticMVarsNoPostponing
      unless (← isDefEq x y) do
        throwError "Expected {y}, but got {← reduce x}"

syntax withPosition("bookExample" ":" term "{{{" ws ident ws "}}}" colGt term:10 colGt "===>" colGt term:10 "end bookExample") : command

elab_rules : command
  | `(bookExample : $type:term {{{ $_name:ident }}} $x:term ===> $y:term end bookExample) =>
    open Lean.Elab.Command in
    open Lean.Elab.Term in
    open Lean.Meta in liftTermElabM <| withDeclName `bookExample do
      let t ← elabTerm type none
      let x ← elabTerm x (some t)
      let y ← elabTerm y (some t)
      synthesizeSyntheticMVarsNoPostponing
      unless (← isDefEq x y) do
        throwError "Expected {y}, but got {← reduce x}"


bookExample {{{ one }}}
  1
  ===>
  1
end bookExample

bookExample {{{ two }}}
  1 + 1
  ===>
  2
end bookExample

syntax withPosition("bookExample" "type" "{{{" ws ident ws "}}}" colGt term:1 colGt "===>" colGt term:1 "end bookExample") : command

elab_rules : command
  | `(bookExample type {{{ $name:ident }}} $x:term ===> $y:term end bookExample) =>
    open Lean.Elab.Command in
    open Lean.Elab.Term in
    open Lean.Meta in liftTermElabM <| withDeclName name.raw.getId do
      let x' ← elabTerm x none
      let xType ← inferType x'
      let y' ← elabTerm y none
      synthesizeSyntheticMVarsNoPostponing
      unless (← isDefEq xType y') do
        throwErrorAt y "Expected the type {y'}, but got {← reduce xType}"

bookExample type {{{ three }}}
  2 + 1
  ===>
  Nat
end bookExample

bookExample type {{{ listT }}}
  List
  ===>
  Type → Type
end bookExample

syntax withPosition("bookExample" "type" "{{{" ws ident ws "}}}" colGt term:10 colGt "<===" colGt term:0 "end bookExample") : command

elab_rules : command
  | `(bookExample type {{{ $name:ident }}} $x:term <=== $y:term end bookExample) =>
    open Lean.Elab.Command in
    open Lean.Elab.Term in
    open Lean.Meta in liftTermElabM <| withDeclName name.raw.getId do
      let y ← elabTerm y none
      let _ ← elabTerm x (some y)
      synthesizeSyntheticMVarsNoPostponing

def nats : (min : Nat) -> (howMany : Nat) -> List Nat
  | n, Nat.zero => [n]
  | n, Nat.succ k => n :: nats (Nat.succ n) k

syntax withPosition("expect" "error" "{{{" ws ident ws "}}}" colGt command "message" str "end" "expect") : command
syntax withPosition("expect" "error" colGt command "message" str "end" "expect") : command

syntax withPosition("expect" "error" "{{{" ws ident ws "}}}" colGt term "message" str "end" "expect") : command
syntax withPosition("expect" "error" colGt term "message" str "end" "expect") : command

-- Compare info and errors modulo leading and trailing whitespace to work around
-- #eval always sticking a \n at the end
def messagesMatch (msg1 msg2 : String) : Bool :=
  let trim str := str.dropWhile (·.isWhitespace) |>.dropRightWhile (·.isWhitespace)
  trim msg1 == trim msg2

def List.containsBy (xs : List α) (pred : α → Bool) : Bool :=
  xs.find? pred |>.isSome

macro_rules
  | `(expect error {{{ $name:ident }}} $expr:term message $msg:str end expect) =>
    `(expect error {{{ $name }}} def x := $expr message $msg end expect)
  | `(expect error $expr:term message $msg:str end expect) =>
    `(expect error def x := $expr message $msg end expect)
  | `(expect error {{{ $_name:ident }}} $cmd:command message $msg:str end expect) =>
    `(expect error  $cmd:command message $msg:str end expect)

elab_rules : command
  | `(expect error $cmd:command message $msg:str end expect) =>
    open Lean.Elab.Command in
    open Lean in
    open Lean.Meta in do
      let savedState <- get
      set { savedState with messages := MessageLog.empty }
      let desiredError := msg.getString
      try
        elabCommand cmd
        let afterState <- get
        let newMessages := afterState.messages.msgs.toList
        let newErrors := newMessages.filter (·.severity == MessageSeverity.error)
        let errStrings <- newErrors.mapM (·.data.toString)
        unless errStrings.containsBy (messagesMatch desiredError) do
          throwError "The desired error {desiredError} was not found in\n{errStrings}"
      finally
        set savedState

expect error {{{ errorEx1 }}}
  def x : Nat := "I am not a Nat"
message
"type mismatch
  \"I am not a Nat\"
has type
  String : Type
but is expected to have type
  Nat : Type"
end expect


syntax withPosition("expect" "info" "{{{" ws ident ws "}}}" colGt command "message" str "end" "expect") : command
syntax withPosition("expect" "info" colGt command "message" str "end" "expect") : command

macro_rules
  | `(expect info {{{ $_name:ident }}} $cmd:command message $msg:str end expect) =>
    `(expect info $cmd:command message $msg:str end expect)

elab_rules : command
  | `(expect info $cmd:command message $msg:str end expect) =>
    open Lean.Elab.Command in
    open Lean in
    open Lean.Meta in do
      let savedState <- get
      set { savedState with messages := MessageLog.empty }
      let desiredInfo := msg.getString
      try
        elabCommand cmd
        let afterState <- get
        let newMessages := afterState.messages.msgs.toList
        let newInfos := newMessages.filter fun m => m.severity == MessageSeverity.information
        let errStrings <- newInfos.mapM fun err => err.data.toString
        unless errStrings.containsBy (messagesMatch desiredInfo) do
          throwError "The desired info {repr desiredInfo} was not found in\n{List.map repr errStrings}"
      finally
        set savedState

expect info {{{ infoEx1 }}}
  #check 1 + 2
message
  "1 + 2 : Nat"
end expect

syntax withPosition("expect" "eval" "info" "{{{" ws ident ws "}}}" colGt term "message" str "end" "expect") : command
syntax withPosition("expect" "eval" "info" colGt term "message" str "end" "expect") : command

macro_rules
  | `(expect eval info {{{ $name:ident }}} $expr:term message $msg:str end expect) =>
    `(expect info {{{ $name }}} #eval ($expr) message $msg end expect)
  | `(expect eval info $expr:term message $msg:str end expect) =>
    `(expect info #eval ($expr) message $msg end expect)

expect eval info {{{ foo }}}
  IO.println "hej" >>= fun _ => IO.println "med dig"
message
"hej
med dig
"
end expect


syntax withPosition("evaluation" "steps" "{{{" ws ident ws "}}}" sepBy1(colGt term, "===>") "end" "evaluation" "steps"): command
elab_rules : command
  | `(evaluation steps {{{ $name }}} $[ $exprs ]===>* end evaluation steps) =>
    open Lean.Elab.Command in
    open Lean.Elab.Term in
    open Lean in
    open Lean.Meta in do
      let mut current : Option Syntax := none
      for item in exprs do
        if let some v := current then
          liftTermElabM <| withDeclName name.raw.getId do
            let x <- elabTerm item.raw none
            let y <- elabTerm v none
            synthesizeSyntheticMVarsNoPostponing
            unless (← isDefEq x y) do
              throwError "Example reduction step {y} ===> {x} is incorrect"
        current := some item.raw

evaluation steps {{{ foo }}}
  1 + 1 + 2
  ===>
  2 + 2
  ===>
  4
end evaluation steps



syntax withPosition("evaluation" "steps" ":" term "{{{" ws ident ws "}}}" sepBy1(colGt term, "===>") "end" "evaluation" "steps"): command
elab_rules : command
  | `(evaluation steps : $ty {{{ $name }}} $[ $exprs ]===>* end evaluation steps) =>
    open Lean.Elab.Command in
    open Lean.Elab.Term in
    open Lean in
    open Lean.Meta in do
      let expected <- liftTermElabM <| withDeclName name.raw.getId <|
        elabTerm ty none <* synthesizeSyntheticMVarsNoPostponing

      let mut current : Option Syntax := none
      for item in exprs do
        if let some v := current then
          liftTermElabM <| withDeclName name.raw.getId do
            let x <- elabTerm item.raw (some expected)
            let y <- elabTerm v (some expected)
            synthesizeSyntheticMVarsNoPostponing
            unless (← isDefEq x y) do
              throwError "Example reduction step {y} ===> {x} is incorrect\n----------\n\t {(← whnf y)}\n ≠\n\t {(← whnf x)}\n----------\n\t {(← reduceAll y)}\n ≠\n\t {(← reduceAll x)}"
        current := some item.raw

evaluation steps : IO Unit {{{ thingy }}}
  let x := 5; IO.println s!"{x}"
  ===>
  IO.println "5"
end evaluation steps

declare_syntax_cat eqSteps

syntax term : eqSteps
syntax term "={" "}=" eqSteps : eqSteps
syntax term "={" term "}=" eqSteps : eqSteps

syntax withPosition("equational" "steps" "{{{" ws ident ws "}}}" (colGt eqSteps) "stop" "equational" "steps") : command
syntax withPosition("equational" "steps" ":" term "{{{" ws ident ws "}}}" (colGt eqSteps) "stop" "equational" "steps") : command

inductive Steps where
  | done : Lean.Syntax → Steps
  | cons : Lean.Syntax → Option Lean.Syntax → Steps → Steps

def Steps.process [Monad m] (forStep : Lean.Syntax × Option Lean.Syntax × Lean.Syntax → m Unit) : Steps → m Unit
  | .done _ => pure ()
  | .cons e1 why (.done e2) => forStep (e1, why, e2)
  | .cons e1 why (.cons e2 why2 more) => do
    forStep (e1, why, e2)
    process forStep (.cons e2 why2 more)

partial def getSteps : Lean.Syntax → Lean.Elab.Command.CommandElabM Steps
  | `(eqSteps|$t:term) => pure (.done t)
  | `(eqSteps|$t:term ={ }= $more:eqSteps) => do
    return (.cons t none (← getSteps more))
  | `(eqSteps|$t:term ={ $why:term }= $more:eqSteps) => do
    return (.cons t (some why) (← getSteps more))
  | other => throwError "Invalid equational steps {other}"

elab_rules : command
  | `(equational steps {{{ $name }}} $stepStx:eqSteps stop equational steps) =>
    open Lean.Elab.Command in
    open Lean.Elab.Term in
    open Lean in
    open Lean.Meta in do
      let exprs ← getSteps stepStx
      if let .done e := exprs then liftTermElabM <| withDeclName name.raw.getId do
        let _ ← elabTerm e none
      exprs.process fun
        | (e1, why, e2) =>
          liftTermElabM <| withDeclName name.raw.getId do
            let x ← elabTerm e1 none
            let y ← elabTerm e2 none
            synthesizeSyntheticMVarsNoPostponing
            match why with
            | none =>
              unless (← isDefEq x y) do
                throwError "Example equational step {y} ===> {x} is incorrect\n----------\n\t {(← whnf y)}\n ≠\n\t {(← whnf x)}\n----------\n\t {(← reduceAll y)}\n ≠\n\t {(← reduceAll x)}"
            | some p =>
              let e1' : TSyntax `term := ⟨e1⟩
              let e2' : TSyntax `term := ⟨e2⟩
              let eq ← elabTermEnsuringType (← `($e1' = $e2')) (some (mkSort Level.zero))
              let _ ← elabTermEnsuringType p (some eq)
              synthesizeSyntheticMVarsNoPostponing
  | `(equational steps : $ty {{{ $name }}} $stepStx:eqSteps stop equational steps) =>
    open Lean.Elab.Command in
    open Lean.Elab.Term in
    open Lean in
    open Lean.Meta in do
      let expected ← liftTermElabM <| withDeclName name.raw.getId (elabType ty)
      let exprs ← getSteps stepStx
      if let .done e := exprs then liftTermElabM <| withDeclName name.raw.getId do
        let _ ← elabTerm e none
      exprs.process fun
        | (e1, why, e2) =>
          liftTermElabM <| withDeclName name.raw.getId do
            let x ← elabTermEnsuringType e1 expected
            let y ← elabTermEnsuringType e2 expected
            synthesizeSyntheticMVarsNoPostponing
            match why with
            | none =>
              unless (← isDefEq x y) do
                throwErrorAt e1 "Example equational step {y} ===> {x} is incorrect\n----------\n\t {(← whnf y)}\n ≠\n\t {(← whnf x)}\n----------\n\t {(← reduceAll y)}\n ≠\n\t {(← reduceAll x)}"
            | some p =>
              let e1' : TSyntax `term := ⟨e1⟩
              let e2' : TSyntax `term := ⟨e2⟩
              let eq ← elabTermEnsuringType (← `(($e1' : $ty) = ($e2' : $ty))) (some (mkSort Level.zero))
              let _ ← elabTermEnsuringType p (some eq)
              synthesizeSyntheticMVarsNoPostponing



equational steps {{{ foo }}}
  1 + 1
  ={
  -- Compute forwards
  rfl
  }=
  2
  ={
  -- Compute backwards
  }=
  0 + 2
stop equational steps

def zipSameLength : List α → List β → Option (List (α × β))
  | [], [] => some []
  | x :: xs, y :: ys => do pure ((x, y) :: (← zipSameLength xs ys))
  | _, _ => none

def Lean.Name.last : Lean.Name -> Option String
  | Lean.Name.str _ s => some s
  | _ => none

syntax "similar datatypes" ident ident : command
elab_rules : command
  | `(similar datatypes $C1:ident $C2:ident) =>
    open Lean.Elab.Command in
    open Lean.Environment in
    open Lean in do
      let e := (<- get).env
      let t1 := C1.getId
      let t2 := C2.getId
      let i1 <- match (e.find? t1).get! with
      | ConstantInfo.inductInfo i => pure i
      | _ => throwError "Not an inductive type: {t1}"
      let i2 <- match (e.find? t2).get! with
      | ConstantInfo.inductInfo i => pure i
      | _ => throwError "Not an inductive type: {t2}"
      if i1.numParams != i2.numParams then throwError "Param count mismatch"
      if i1.numIndices != i2.numIndices then throwError "Index count mismatch"
      if i1.isRec != i1.isRec then throwError "Recursiveness mismatch"
      let ctors <- match zipSameLength i1.ctors i2.ctors with
      | some v => pure v
      | none => throwError "Different number of constructors"
      for (c1, c2) in ctors do
        let (n1, n2) := (c1.last.get!, c2.last.get!)
        if n1 != n2 then throwError "Constructor name mismatch: {n1} vs {n2}"
        let ctor1 <- match (e.find? c1).get! with
        | ConstantInfo.ctorInfo i => pure i
        | _ => throwError "Not a constructor {c1}"
        let ctor2 <- match (e.find? c2).get! with
        | ConstantInfo.ctorInfo i => pure i
        | _ => throwError "Not a constructor {c2}"
        if ctor1.numFields != ctor2.numFields then throwError "Constructor field count mismatch for {n1}"


namespace Foo
  inductive List (α : Type) : Type where
    | nil : List α
    | cons : α -> List α -> List α
end Foo

similar datatypes List Foo.List
