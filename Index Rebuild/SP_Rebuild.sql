/* 
    Procédure de rebuild des index de la base dans laquelle se trouve la procédure. 

*/ 

CREATE OR ALTER PROCEDURE SP_Rebuild
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
AS 

    SET NOCOUNT ON; 

    DECLARE @RS             INT = 0;
    DECLARE @SQL            NVARCHAR(MAX);
    DECLARE @TABLE_NAME     SYSNAME; 
    DECLARE @SCHEMA_NAME    SYSNAME;
    DECLARE @INDEX_NAME     SYSNAME;
    DECLARE @FRAG           DECIMAL(9,2);

    DECLARE @COMMANDS TABLE (
        DATA        NVARCHAR(100),
        SQLCOMMAND  NVARCHAR(300)
    )
    DECLARE @ERRORS TABLE (
        DATA            NVARCHAR(100)   COLLATE database_default,
        TABLE_NAME      SYSNAME         COLLATE database_default,
        SCHEMA_NAME     SYSNAME         COLLATE database_default,
        INDEX_NAME      SYSNAME         COLLATE database_default,
        ERRORMESSAGE    NVARCHAR(1000)  COLLATE database_default
    )

    DECLARE @TABLES_FILTERS TABLE (
        TABLE_FULL_NAME NVARCHAR(256) COLLATE database_default
    )


    IF @reorganizeMinFragmentationPercent >= @rebuildMinFragmentationPercent
    BEGIN 
        DECLARE @Error NVARCHAR(100) = 'Le niveau min pour le reorganize ne doit pas être égal ou supérieur au niveau min de rebuild.';
        SET @RS = -1;
        THROW 51000, @Error, 1;  
    END


    -- Report DATA
    IF @report = 1
    BEGIN 

         SELECT 
            'HEAP TABLES REPORT' AS Data,
            Heap.name AS HeapTableName,
            PS.object_id, 
            PS.page_count, 
            PS.record_count, 
            PS.avg_fragmentation_in_percent           
        FROM (
            SELECT 
                o.object_id, 
                o.name
            FROM sys.indexes AS i 
                INNER JOIN sys.objects AS o ON o.object_id = i.object_id
            WHERE i.type_desc = 'HEAP'
                AND o.type_desc = 'USER_TABLE'
        ) Heap
            CROSS APPLY sys.dm_db_index_physical_stats(DB_ID(), Heap.object_id, 0, NULL, NULL) AS PS
        WHERE PS.alloc_unit_type_desc = 'IN_ROW_DATA'
        ORDER BY PS.avg_fragmentation_in_percent DESC

        SELECT 
            'INDEX REPORT' AS Data,
            S.name as 'Schema',
            T.name as 'Table',
            I.name as 'Index',
            PS.avg_fragmentation_in_percent,
            PS.page_count
        FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS PS
            INNER JOIN sys.tables T on T.object_id = PS.object_id
            INNER JOIN sys.schemas S on T.schema_id = S.schema_id
            INNER JOIN sys.indexes I ON I.object_id = PS.object_id
                AND PS.index_id = I.index_id
        WHERE PS.database_id = DB_ID()
            AND I.name IS NOT NULL
        ORDER BY PS.avg_fragmentation_in_percent DESC

    END

    -- Determine la liste des tables à rebuild 
    IF @TablesFilters IS NULL OR @TablesFilters = ''
    BEGIN 
        INSERT INTO @TABLES_FILTERS 
        SELECT 
            CONCAT(TABLE_SCHEMA, '.', TABLE_NAME) COLLATE database_default
        FROM INFORMATION_SCHEMA.TABLES
    END 
    ELSE 
    BEGIN 
        INSERT INTO @TABLES_FILTERS 
        SELECT 
            value AS TABLE_FULL_NAME
        FROM string_split(@TablesFilters, ',')
    END

    -- Rebuild HEAP
    IF @rebuildHeapTables = 1
    BEGIN 

        DECLARE C_HEAP CURSOR LOCAL FORWARD_ONLY STATIC READ_ONLY
        FOR 
            SELECT 
                Heap.table_name,
                Heap.schema_name
            FROM (
                SELECT 
                    o.object_id, 
                    o.name AS table_name, 
                    s.name AS schema_name
                FROM sys.indexes AS i 
                    INNER JOIN sys.objects AS o ON o.object_id = i.object_id
                    INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
                WHERE i.type_desc = 'HEAP'
                    AND o.type_desc = 'USER_TABLE'
            ) Heap
                CROSS APPLY sys.dm_db_index_physical_stats(DB_ID(), Heap.object_id, 0, NULL, NULL) AS PS                     
                INNER JOIN @TABLES_FILTERS T ON T.TABLE_FULL_NAME = CONCAT( Heap.schema_name, '.', Heap.table_name)  COLLATE database_default
            WHERE PS.avg_fragmentation_in_percent >= @rebuildMinFragmentationPercent
                AND PS.alloc_unit_type_desc = 'IN_ROW_DATA'
        
        OPEN C_HEAP;
        FETCH C_HEAP INTO @TABLE_NAME, @SCHEMA_NAME;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            
            SET @SQL = CONCAT('ALTER TABLE ', @SCHEMA_NAME, '.', @TABLE_NAME, ' REBUILD'); 

            IF @online = 1 
            BEGIN 
                SET @SQL = CONCAT(@SQL, ' WITH (ONLINE=ON)')
            END

            SET @SQL = CONCAT(@SQL, ';');

            INSERT INTO @COMMANDS(DATA, SQLCOMMAND) VALUES ('HEAP REBUILD COMMAND', @SQL);

            IF @execCommands = 1
            BEGIN 
                BEGIN TRY 
                    EXEC (@SQL)
                END TRY 
                BEGIN CATCH 
                    SET @RS = -1; 
                    INSERT INTO @ERRORS(DATA, TABLE_NAME, ERRORMESSAGE) VALUES ('HEAP REBUILD ERROR', @TABLE_NAME, COALESCE(ERROR_MESSAGE(), 'Unknow Error'))
                END CATCH   
            END

            FETCH C_HEAP INTO @TABLE_NAME, @SCHEMA_NAME;

        END

        CLOSE C_HEAP;
        DEALLOCATE C_HEAP;

    END

    -- Rebuild INDEX
    IF @rebuildIndex = 1
    BEGIN 

        DECLARE C_INDEX CURSOR LOCAL FORWARD_ONLY STATIC READ_ONLY
        FOR 
            SELECT 
                S.name as 'Schema',
                T.name as 'Table',
                I.name as 'Index', 
                DDIPS.avg_fragmentation_in_percent
            FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS DDIPS
                INNER JOIN sys.tables T on T.object_id = DDIPS.object_id
                INNER JOIN sys.schemas S on T.schema_id = S.schema_id
                INNER JOIN sys.indexes I ON I.object_id = DDIPS.object_id
                    AND DDIPS.index_id = I.index_id
                INNER JOIN @TABLES_FILTERS TF ON TF.TABLE_FULL_NAME = CONCAT( S.name, '.', T.name) COLLATE database_default
            WHERE DDIPS.database_id = DB_ID()
                AND I.name IS NOT NULL
                AND DDIPS.avg_fragmentation_in_percent >= @reorganizeMinFragmentationPercent

        OPEN C_INDEX;
        FETCH C_INDEX INTO @SCHEMA_NAME, @TABLE_NAME, @INDEX_NAME, @FRAG;

        WHILE @@FETCH_STATUS = 0
        BEGIN

            SET @SQL = CONCAT('ALTER INDEX ', @INDEX_NAME, ' ON ', @SCHEMA_NAME, '.', @TABLE_NAME); 

            IF @FRAG >= @reorganizeMinFragmentationPercent AND @FRAG < @rebuildMinFragmentationPercent
            BEGIN 
                SET @SQL = CONCAT(@SQL, ' REORGANIZE');
            END
            ELSE IF @FRAG > @rebuildMinFragmentationPercent
            BEGIN 
                SET @SQL = CONCAT(@SQL, ' REBUILD');
                IF @online = 1  
                BEGIN 
                    SET @SQL = CONCAT(@SQL, ' WITH (ONLINE=ON)')
                END
            END   
            ELSE 
            BEGIN   
                SET @SQL = NULL;
            END
            
            SET @SQL = CONCAT(@SQL, ';');

            IF @SQL IS NOT NULL 
            BEGIN 
                INSERT INTO @COMMANDS(DATA, SQLCOMMAND) VALUES ('INDEX REBUILD COMMAND', @SQL);

                IF @execCommands = 1
                BEGIN 
                    BEGIN TRY 
                        EXEC (@SQL)
                    END TRY 
                    BEGIN CATCH 
                        SET @RS = -1; 
                        INSERT INTO @ERRORS(DATA, SCHEMA_NAME, TABLE_NAME, INDEX_NAME, ERRORMESSAGE) VALUES ('INDEX REBUILD ERROR', @SCHEMA_NAME, @TABLE_NAME, @INDEX_NAME, COALESCE(ERROR_MESSAGE(), 'Unknow Error'))
                    END CATCH   
                END
            END

            FETCH C_INDEX INTO @SCHEMA_NAME, @TABLE_NAME, @INDEX_NAME, @FRAG;

        END

        CLOSE C_INDEX;
        DEALLOCATE C_INDEX;
    END

    -- Update STATS
    IF @updateStatistics = 1 AND @execCommands = 1
    BEGIN 
        BEGIN 
            BEGIN TRY 
                EXEC sp_updatestats;
            END TRY 
            BEGIN CATCH 
                SET @RS = -1; 
                INSERT INTO @ERRORS(DATA, TABLE_NAME, ERRORMESSAGE) VALUES ('UPDATE STATS ERROR', @TABLE_NAME, COALESCE(ERROR_MESSAGE(), 'Unknow Error'))
            END CATCH   
        END
    END

    -- PRINT Commands
    IF @printCommand = 1 
    BEGIN 
        SELECT 
            *
        FROM @COMMANDS
    END

    -- PRINT Errors
    IF @reportErrors = 1 
    BEGIN 
        SELECT 
            *
        FROM @ERRORS
    END

RETURN @RS
