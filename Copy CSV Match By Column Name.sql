/*
  Created Aug 2020 - Steve Segal
 This proc will load a file that has column headers, into a Snowflake table,  using the copy command
 It allows the columns to be in any order, The Copy statement is dynamically generated 
 This proc will load the files in the STAGE/PATH param and then Copy the data into the table in the TABLE_NAME param
 Parameters
 TABLE_NAME: Name of the table to load
 STAGE: Name of the stage Example: MY_S3_STAGE
 PATH: Path to the directory or file. Does not include the stage. Example: 2020/March/file123.csv
 NUMBER_OF_COLUMNS: The number of columns in the file. If set to -1 then it will be determined. It will be a little slower, but not much
 Returns the number of files processes
 Example: merge_file_into_table('tableabc1','MY_INTERNAL_STAGE','tableabc1.csv',-1);
 ** Prereq** The user must have the ability to alter the stage becuse of the Skip_header =1 statement
 Versions
 1.1.0 - Initial release
*/
--**************************  create_table_from_file_and_load_work  **************************

create or replace procedure copy_file_match_column_by_name (TABLE_NAME STRING, STAGE STRING, PATH STRING, NUMBER_OF_COLUMNS DOUBLE)
  returns string
  language javascript strict
  execute as caller
  as
$$ 
var stageFullPath = "@"+STAGE+"/"+PATH; 
var alterStageHeader0 =`alter stage ${STAGE} set FILE_FORMAT = (FIELD_OPTIONALLY_ENCLOSED_BY = '"', SKIP_HEADER=0);`
var alterStageHeader1 =`alter stage ${STAGE} set FILE_FORMAT = (FIELD_OPTIONALLY_ENCLOSED_BY = '"', SKIP_HEADER=1);`
var emptyFile = true;
var columnName =" ";
var TableCols = "";
var FileCols = "";
var stmt="";
var fileAlias = "fileSource";
var sql="";
var uploadStmt="";
var newLine = "\r\n";
var columnDelimiter ='~';
var arrayColunmNamesFromFile;
var ordinal = 0;
var returnVal="";
var result="";
var val="";

try{
     //Check if params exists
    if(!TABLE_NAME || !STAGE || !PATH ){
      return `Error: At least one paramter is null: TABLE_NAME=${TABLE_NAME}, STAGE=${STAGE}, PATH=${PATH})`
    }
    // We are first retreiving headers so skip_header = 0
    snowflake.execute({ sqlText: alterStageHeader0}); 
//*************  Get the number columns in the file *************//   ex. select concat($1,',',$2) ...
    try{
        var i;      
        if(NUMBER_OF_COLUMNS>-1)
        {numOfBatchColumns=NUMBER_OF_COLUMNS;}
        else
        {
            //One way to get the number of columns is to use the count of cols from information_schema. That would be the max. Seems slower so I'll use the next approach
            //sqlStmt = `select count(*) from information_schema.columns where table_name=upper('${TABLE_NAME}')`
            //This gets column values spaced apart and returns the first one that is null. We can use that as the last column.
          sqlStmt = `select iff($100 is null,'100',iff($300 is null,'300',iff($600 is null,'600',iff($900 is null,'900',iff($1200 is null,'1200',iff($1500 is null,'15000','')))))) from ${stageFullPath}  limit 1 offset 0`;
          var stmtGetFirstRow = snowflake.execute({ sqlText: sqlStmt});      
          stmtGetFirstRow.next();      
          numOfBatchColumns = stmtGetFirstRow.getColumnValue(1);          
        }
//*************  Create the select statemnt *************//   ex. select concat($1,',',$2) ...        
        selectStmt="";
        for (i = 1; i <= numOfBatchColumns; i++) {
            selectStmt+=",'"+columnDelimiter+"',IfNULL($"+i+",'')";
        }
        //Get first row in file 
        sqlStmt = `select concat(${selectStmt.substring(5)}) from ${stageFullPath} limit 1;`;
        var stmtGetFirstRow = snowflake.execute({ sqlText: sqlStmt});
        stmtGetFirstRow.next();
        var val = stmtGetFirstRow.getColumnValue(1);
        //Create an array of the column names
        arrayColunmNamesFromFile = val.split(columnDelimiter);
        columnName = arrayColunmNamesFromFile[0];
        ordinal = 0;
    }
    catch(err){
      if(err.message.includes("ResultSet is empty or not prepared")) {               
        return('Copy executed with 0 files processed.')
      }
      throw (err);
    }
//************* Build the table col and file column clauses ex. col1,col2,col3..  and $1,$2,$3... *************//  
    while (columnName)
    {
        emptyFile = false;
        ordinalForSelect = ordinal + 1; // have to do this becuase the arrays start at 0 but the columns start at 1       
        FileCols += ",$" + ordinalForSelect;  
        TableCols +=  ", " + columnName; 
        ordinal+=1;
        columnName = arrayColunmNamesFromFile[ordinal];       
    }
    if(emptyFile)
      {return "No data in first cell"}
    else{
        TableCols = TableCols.substring(1); //Remove leading comma
        FileCols = FileCols.substring(1); //Remove leading comma
        uploadStmt = `copy into ${TABLE_NAME} (${TableCols}) from  (select ${FileCols} from ${stageFullPath});` 
//************* Final SQL Statement *************//        
        try{
          snowflake.execute({ sqlText: alterStageHeader1}); // ingore the header row
          stmt = snowflake.execute({ sqlText: uploadStmt});
          stmt.next(); 
        }
        catch(err){
          if(err.message.includes("is not recognized")) {
            return("ERROR: Datatype incorrectly set. "+err)
          }        
          throw(err)
        }
//************* Get Result *************// 
    val = `${stmt.getColumnValue(1)}`
    if (val.includes("Copy executed with 0 files processed")){
       return val 
    }
    else{
          var i = 1;
          var file = "file" // Handling singular/plural
//************* Loop to find number of files processed *************//           
          while(stmt.next())
          {
            file = "files"
            i = i+1;
          }
        return `Copy executed with ${i} ${file} processed.`
     }
   }
}
catch(err){
    throw(err)
}
$$;