grammar Expr;

expr : expr '*' expr | ID ;

ID : [a-z]+ ;
WS : [ \t\r\n]+ -> skip ;
