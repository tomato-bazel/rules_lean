import Pg.Catalog.Tables
import Pg.Query.Top

namespace App

def summary : String :=
  match Pg.Query.sample with
  | .createSchema name => Pg.Catalog.seed.name ++ ":" ++ name

end App
