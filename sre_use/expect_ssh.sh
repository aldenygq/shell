#! /usr/bin/ expect
set timeout 5
set hostname [l index $argv 0 ]
set password [l index $argv 1]
spawn ssh $hostname
expect {
"Connection refused" exit ##连接失败情况，比如对方ssh服务关闭
"Name or service not known" exit ##找不到服务器，比如输入的IP地址不正确
" (yes/no)" {send "yes\r" ;exp_ continue}
"password:" {send "$password\r"}
interact
exit #interact后的命令不起作用
