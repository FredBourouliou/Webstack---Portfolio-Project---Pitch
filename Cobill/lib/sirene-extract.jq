.results[0] // {}
| [
    (.nom_complet // ""),
    ((.siege.adresse // "") | gsub("\\s+\\d{5}\\s+\\S+\\s*$"; "")),
    (.siege.code_postal // ""),
    (.siege.libelle_commune // "")
  ]
| join("\n")
