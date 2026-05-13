(.results[0] // {}) as $r
| ($r.matching_etablissements[0] // $r.siege // {}) as $e
| [
    ($r.nom_complet // ""),
    (($e.adresse // "") | gsub("\\s+\\d{5}\\s+\\S+\\s*$"; "")),
    ($e.code_postal // ""),
    ($e.libelle_commune // "")
  ]
| join("\n")
