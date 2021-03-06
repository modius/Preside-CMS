component output=false hint="Proxy to cfdbinfo for returning information about a database and its objects" singleton=true {

// CONSTRUCTOR
	public any function init() output=false {
		return this;
	}

// PUBLIC API METHODS
	public query function getDatabaseVersion( required string dsn ) output=false {
		var db = "";

		dbinfo type="version" datasource=arguments.dsn name="db";

		return db;
	}

	public query function getTableInfo( required string tableName, required string dsn ) output=false {
		var table = "";

		dbinfo type="tables" name="table" pattern="#arguments.tableName#" datasource="#arguments.dsn#";

		return table;
	}

	public query function getTableColumns( required string tableName, required string dsn ) output=false {
		var columns = "";

		dbinfo type="columns" name="columns" table=arguments.tableName datasource=arguments.dsn;

		return columns;
	}

	public struct function getTableIndexes( required string tableName, required string dsn ) output=false {
		var indexes = "";
		var index   = "";
		var ixs     = {};

		dbinfo type="index" table="#arguments.tableName#" name="indexes" datasource="#arguments.dsn#";

		for( index in indexes ){
			if ( index.index_name neq "PRIMARY" ) {
				if ( not StructKeyExists( ixs, index.index_name ) ){
					ixs[ index.index_name ] = {
						  unique = not index.non_unique
						, fields = ""
					}
				}

				ixs[ index.index_name ].fields = ListAppend( ixs[ index.index_name ].fields, index.column_name );
			}
		}

		return ixs;
	}

	public struct function getTableForeignKeys( required string tableName, required string dsn ) output=false {
		var keys        = "";
		var key         = "";
		var constraints = {};
		var rules       = {};

		rules["0"] = "cascade";
		rules["2"] = "set null";

		dbinfo type="foreignKeys" table=arguments.tableName datasource="#arguments.dsn#" name="keys";
		for( key in keys ){
			constraints[ key.fk_name ] = {
				  pk_table  = key.pktable_name
				, fk_table  = key.fktable_name
				, pk_column = key.pkcolumn_name
				, fk_column = key.fkcolumn_name
			}

			if ( StructKeyExists( rules, key.update_rule ) ) {
				constraints[ key.fk_name ].on_update = rules[ key.update_rule ];
			} else {
				constraints[ key.fk_name ].on_update = "error";
			}

			if ( StructKeyExists( rules, key.delete_rule ) ) {
				constraints[ key.fk_name ].on_delete = rules[ key.delete_rule ];
			} else {
				constraints[ key.fk_name ].on_delete = "error";
			}
		}

		return constraints;
	}
}