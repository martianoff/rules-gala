grammar Expr;

expr : ID ('*' ID)* ;

ID : [a-z]+ ;
WS : [ \t\r\n]+ -> skip ;
