import App.Bridge

def main (args : List String) : IO UInt32 := do
  IO.println (App.summary ++ "|" ++ String.intercalate "|" args)
  return 0
