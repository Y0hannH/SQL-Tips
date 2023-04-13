# Index Rebuild 

Procédure stockée standerd permettant de rebuild des index dans la base ou elle est deployée. 


## Utilisation 

Détail de l'utilisation de la procédure. 

### Paramètres 

```
 -- Affichage de la fragmentation. Oui par défaut
    @report                                 BIT = 1,

    -- Affichage des requêtes SQL de rebuild générées. Oui Par défaut
    @printCommand                           BIT = 1,

    -- Exécuter les requêtes SQL de rebuild généré. Non par défaut
    @execCommands                           BIT = 0,

    -- Exécuter les rebuild en mode Online. Oui par défaut
    @online                                 BIT = 1,

    -- Niveau minimum de fragmentation pour lancer un rebuild. 30 par défaut
    @rebuildMinFragmentationPercent         INT = 30,

    -- Niveau minimum de fragmentation pour lancer un reoganize. 10 par défaut
    @reorganizeMinFragmentationPercent      INT = 10,

    -- Exécuter le rebuild sur les tables HEAPS. Oui par défaut
    @rebuildHeapTables                      BIT = 1, 

    -- Exécuter le rebuild sur les index. Oui par defaut
    @rebuildIndex                           BIT = 1,

    -- Exécuter le recalcul des statistiques. Non par défaut
    @updateStatistics                       BIT = 0, 

    -- Afficher les erreurs. Oui par défaut
    @reportErrors                           BIT = 1, 

    -- Tables à rebuild. Les autres seront ignorées. Format liste séparée par des virgules : schema.table,schema.table2 [...]
    @TablesFilters                          NVARCHAR(1000) = ''
``` 

### Exemple 

``` 
-- Affichage de la fragmentation et des requêtes qui sont à exécuter. Pas d'exécution
EXEC SP_Rebuild

-- Afficahe de la fragmentation seulement . Pas d'exécution 
EXEC SP_Rebuild @report = 1, @printCommand = 0

-- Exécuter le rebuild 
EXEC SP_Rebuild @execCommands = 1

-- Modifier les niveaux minimum de déclenchement du rebuild
EXEC SP_Rebuild @report = 1, @printCommand = 1, @reorganizeMinFragmentationPercent = 30, @rebuildMinFragmentationPercent = 50
``` 
