tol.err = 1e-4
log.lik<-function(obj, b, Psi){
    ## obj := an object from class 'cglmm'
    ## b is an m x n matrix of random effects, for m replication for each unit n
    ## Psi is the covariance matrix 
    sig= sig.auto(obj,obj$xi)
    if(missing(Psi)) Psi = sig -obj$delta%*%t(obj$delta)
    ## log likelihood for all, faster method.
    inv.psi=  pd.solve(Psi, silent=TRUE, log.det=TRUE)
    det.psi =  attributes(inv.psi)$log.det
    d = obj$delta
    G_in = obj$G
    dv = unlist(lapply(obj$v, function(r) r*d))
    Zin = unlist(obj$Z)
    z = Zin-  dv
    ## Addition
    param = c(solve(sqrtm(sig))%*%d)
    param = param/sqrt(1-t(param)%*%param)
    lambda_unit = d/sqrt(1-d^2)
    aux = apply(b,1, function(s){
        dd = obj$D*s
        s = matrix(s)
        zzz = matrix(Zin -s, ncol=obj$obs, byrow=TRUE)
        #sum(tapply(z-dd, obj$levels, function(zz){
        #    -.5*det.psi- .5*t(zz) %*% inv.psi %*%(zz)
        #}))+
        mle.sn(param, zzz,sig)+
            +sum(sapply(1:ncol(zzz), function(i) mle.sn(lambda_unit[i],zzz[,i], 1)))+
            #-0.5*sum(((z -dd)^2)/(1-obj$delta^2) + log(1-obj$delta^2))+
                +obj$glm.fun(x = obj$glm.link(obj$X%*%obj$B+dd),obj$Y)+
                    ## Random effect
                    + sum(sapply(s, function(r) -0.5*log(G_in) -.5 *t(r)%*%r/obj$G))/obj$obs +
                        -0#sum(v^2/2)
    })
    mean(aux)
}

B_analytic<-function(obj,link,b){
    ## estimating fixed effect analytically
    if (obj$q>1){
        DD = lapply(1:NROW(b[[1]]),
            function(i) unlist(lapply(1:obj$units,
                                      function(j)  obj$D[obj$levels==j,]%*%b[[j]][i,])))
    }
    if (obj$q==1)
        DD = apply(b, 1, function(r) obj$D*r)
    
    if(obj$p>1){
        if(link =="exp") {
            mu  = matrix(rowMeans(apply(DD, 2, function(a) obj$SXXlY -obj$SXX%*%a )))
            temp = c(obj$X[,-1]%*%mu[-1])
            mu[1] = mean(log(obj$Y%*%exp(-DD - temp)/obj$n))
        }
        if(link =="inv"){
            mu = rowMeans(sapply(DD, function(a)obj$SXX%*%(1/obj$Y) - obj$SXX%*%a ))
            mu = matrix(rowMeans(apply(DD, 2, function(a)obj$SXX%*%(1/obj$Y) - obj$SXX%*%a )))
        }
    }
    if(obj$p==1){
        if(link == 'exp') mu = matrix(mean(log(obj$Y%*%exp(-DD)/obj$n)))
        if(link =="inv")  mu = matrix(mean(sapply(DD, function(a)obj$SXX%*%(1/obj$Y) - obj$SXX%*%a )))
    }
    mu
}

sig.beta.optim<-function(obj,b, Psi, MLE = TRUE){
    ## THE MLE Maximum estimate of a multivariate distribution
    if(MLE){
        mean(apply(b, 1, var))
    }else{
        G.in<-function(i){
            spsi=pseudoinverse(Psi)
            x = t(obj$D[obj$levels== i,])%*%spsi%*%obj$D[obj$levels== i,]
            H = tauH[i]
            solve(solve(H) - x)
        }
        mean(sapply(1:obj$units, function(i) G.in(i)))
    }
}

sig.auto <-	function(obj,p = obj$xi)
    ## Calculates the auto-regressive co-variance matrix Sigma based on xi
    round(obj$auto(obj$xpnd(obj$T[obj$levels==1]))^(-p),3)


ZGenFromY<-function(obj,blist, mean = TRUE){
    ## Given Y, estimate Z by distribution transformation
    ## mean=TRUE does the transformation T as T(E(b)), rather than E(T(b))
    ## where b is the random effect variable. The former is faster but not exact as a result of convexity.
    if(mean){
        b = sapply(blist, mean)
        Db = obj$D*rep(b, each= obj$obs)
        x = obj$glm.link(obj$X %*% obj$B + Db)
        pp = obj$glm.pfun(x,  obj$Y)
        pp[which(pp>.999999)]=.9999
        pp[which(pp<.000001)]=.0001
        lambda_unit = obj$delta/sqrt(1-obj$delta^2)
        sapply(1:length(pp), function(r) 
            qsn(pp[r], xi=Db[r], omega=1, alpha=lambda_unit[r],lower.tail=TRUE))  
    } else{
        bb =  lapply(1:NROW(blist[[1]]), function(i) t(sapply(1:obj$units, function(j) blist[[j]][i,])))
        z=  sapply(bb, function(b){
            Db = obj$D*rep(b, each= obj$obs)
            x = obj$glm.link(obj$X %*% obj$B + Db)
        pp = obj$glm.pfun(x,  obj$Y)
        pp[which(pp>.999999)]=.9999
        pp[which(pp<.000001)]=.0001
        lambda_unit = obj$delta/sqrt(1-obj$delta^2)
        sapply(1:length(pp), function(r) 
            qsn(pp[r], xi=Db[r], omega=1, alpha=lambda_unit[r],lower.tail=TRUE))  
    })
    rowMeans(z)
    }
}

bGen.single<-function(obj,n, Psi){
    ## Random effect generator for each level i. Generates n copies
    spsi=  pd.solve(Psi, silent=TRUE)
    x = t(obj$D[obj$levels== 1,])%*%spsi%*%obj$D[obj$levels== 1,]
    tau2 =solve( solve(obj$G)+ x)
    if(tau2<0)
        tau2=tol.err
    dz = obj$Z  - rep(obj$delta,obj$units) *rep(obj$v, each = obj$obs)
    dd = obj$D[1:obj$obs]
    tapply(dz, obj$levels, function(zz){
        mu = c(tau2%*%t(dd)%*%spsi%*%zz)
        mvrnorm(n=n,  mu=mu, Sigma=tau2)
    }, simplify = FALSE)
}

psi.llk<-function(obj,b.ln, sig.old){
    ## Estimates the matrix Psi and hence xi and delta.
    ##s = t(sapply(1:obj$units, function(r) Z_o[[r]] - mean(b.ln[[r]])))
    Z = do.call('rbind',tapply(obj$Z, obj$levels, function(r)r))
    s = t(sapply(1:obj$units, function(r) Z[r,] - mean(b.ln[[r]])))
    alpha = c(solve(sqrtm(sig.old))%*%obj$delta)
    alpha =  alpha/sqrt(1-min(0.99,t(alpha)%*%alpha))
    fit = msn.mle(y= s, start=list(rep(0, obj$obs), Omega = sig.old, alpha = alpha),opt.method="BFGS")
    sig.temp = fit$dp$Omega;sig.temp
    eta = sqrt(diag(sig.temp))
    sig.temp = cov2cor(sig.temp)
    hxi =-log(sig.temp)/ obj$xpnd(obj$T[obj$levels ==1])
    hxi =mean(hxi[lower.tri(hxi)], na.rm =TRUE)
    hxi = max(0.1, hxi)
    sig.temp = sig.auto(obj,p=hxi)
    lam = fit$dp$alpha/eta
    lam = rep( mean(lam), obj$obs)
    ##lam = rep(1, obj$obs)
    alpha = lam/sqrt(1+t(lam)%*%lam)
    delta = sqrtm(sig.temp)%*%alpha
    delta= sign(delta)*pmin(0.99, abs(delta)) ## from wiki notes
    psi  = sig.temp -delta%*%t(delta)
    list(Psi = psi , xi =hxi, delta = delta, sig = sig.temp)
}

mle.sn<-function (param, y, Omega) {
    ## MLE of a Skew-normal used in many functions above
    y = data.matrix(y)
    x <- data.matrix(rep(1, nrow(y)))
    d <- ncol(y)
    w <- rep(1, nrow(y))
    n <- sum(w)
    p <- ncol(x)
    beta <- rep(0, p,d)
    eta <- param
    y0 <- y - x %*% beta
    D <- diag(qr(2 * pi * Omega)[[1]])
    logDet <- sum(log(abs(D)))
    dev <- n * logDet - 2 * sum(zeta(0, y0 %*% eta) * w) + n * d
    dev/(-2)
}


best_cglmm<-function(obj, b_o, lambda){
    ##    source('functions.R', local=TRUE)
    ## calculates the log-likelihood given the original random effect variable (b_o)
    Sig <-sig.auto(obj,obj$xi)
	obj$v <- abs (rnorm(obj$units,0,1))
    l = lambda
    l = l/sqrt(1+ t(l)%*%l)
    delta = sqrtm(Sig)%*%l
	Psi<- Sig-obj$delta%*%t(obj$delta)
    
    obj$Z<- if(is.null(obj$Z)) unlist(Z.raw.hat(lapply(1:units, function(r) rbind(b_o[[r]], b_o[[r]])))) else 
    obj$Z
    
    b.ln.m  = do.call('cbind', b_o)
    b.ln.m = t(apply(b.ln.m, 1, function(r) rep(r, each= obj$obs)))
    ## Best log-likelihood
    log.lik(obj, b.ln.m, Psi)
}