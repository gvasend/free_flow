USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM "file:///FPDSNG_Contracting_Offices.csv" AS csvLine
 CREATE (p:gate { id: toInt(csvLine.id) , defer_link_to__: csvLine.defer_link_to__ , text: csvLine.text , filename: csvLine.filename , absolute_file_name: csvLine.absolute_file_name , type: csvLine.type , created: csvLine.created , contents: csvLine.contents  }) ;
CREATE CONSTRAINT ON (n:gate) ASSERT n.id is UNIQUE;
