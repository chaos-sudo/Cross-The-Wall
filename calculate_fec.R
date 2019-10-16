factorial <- function(n)
{
	# 阶乘计算
	return( ifelse(n < 2, 1, n * factorial(n - 1)) )
}

cdfBinom <- function(n, k, p)
{
	# 二项分布累计分布函数计算
	return( factorial(n) / factorial(k) / factorial(n - k) * p^k * (1-p)^(n - k) )
}

predictFEC <- function(rid = 0.4, base = 2, extra = 4)
{
	# 给出FEC预定值，预测理论延迟
	return( sum(sapply(0:extra, function(y) cdfBinom(base + extra, y, rid))) )
}

genExtra <- function(rid = 0.4, base = 2, probExp = 0.99, kmax = 2)
{
	# 给出真实延迟，数据包数量，和延迟期望值，生成达到期望值的最小冗余包数量
	extraCand <- 0:(kmax*base)
	winResult <- sapply(extraCand, function(extra) predictFEC(rid, base = base, extra = extra))
	# 选择达到期望值的最小冗余包数量，如果没有达到期望值的，择选最优解
	id <- ifelse(sum(winResult > probExp) == 0, length(extraCand), min(which(winResult > probExp)))
	return( unlist(cbind(extraCand, winResult)[id,]) )
}

recommFEC <- function(sent, received)
{
	# 给出单通道中，eg. client->server | server->client，数据包的发送和接收数量，计算推荐FEC配置
	rid = 1 - received / sent
	bases <- c(2, 10, 20)
	# 可选的数据包发送基数
	# bases <- 2*(1:10)
	# 可选的延迟期望值控制函数，对于真实延迟不错的选择较高期望，对于实际延迟非常差的则不做过高期待
	probExp <- ifelse(rid > 0.2, 0.99, ifelse(rid > 0.1, 0.999, 0.9999))
	result <- sapply(bases, function(base) genExtra(rid, base, probExp) )
	return( data.frame(nData = bases, nRddt = result[1,], pWin = result[2,]) )
	
}

genFEC <- function(sent, received)
{
	# 这是利用R内置函数qbinom进行计算的另一版本，差别在于首先给出的不是数据包发送基数，而是总数据包数量
	rid = 1 - received / sent
	# sapply(c(6,8,10,16,20,30,40,50), 
	sapply(2*(1:20), 
		   function(size)
		   {
		   		a <- qbinom(p=0.999, size, prob = rid)
		   		return( c(size-a, a, size) )
		   }
	)
}

server_fec = 93462
client_fec = 91031
# recommFEC(server_fec, client_fec)
# genFEC(server_fec, client_fec)
1-client_fec/server_fec
predictFEC(1-client_fec/server_fec, 2, 4)
