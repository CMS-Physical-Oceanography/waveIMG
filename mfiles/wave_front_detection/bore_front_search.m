function [xylog,bblog,fnlog] = bore_front_search_v5(Q0,nx,ny,r0,Qmin,Qstd,Nstd,plotter);
%
% USAGE: xylog= bore_front_search_v2(Q0,nx,ny,r0,Qmin,Qstd,Nstd);
%
% this is an iterative searcher. start at the location w/
% maximum Q0, move outward... then restart.
% The shore should be close to the bottom of the image (small y==offshore)
% method based on Celona et al 2019 (not sure of year)
%
% $$$ figure, imagesc(Q0)
ax = gca;
if ~exist('plotter','var')
    plotter=0;
end
%
% radon transform resolution (want pixel in center of circle)
if ~iseven(r0)
    r0 = r0+1;
end
%
if r0<25
    threshold=3;% half pixel threshold distance from max of radon transform for r0=25 (I think this is 5m)
    np_min = r0/3;% there must be at least this many points along radon identified ridge, (~2m long front)
    dr = 1;
else
    threshold=0.5;% half pixel threshold for r0=100
    np_min = r0/4;
    dr = 2;
end
dT = pi/90;
%
% grid indices
[XX,YY] = meshgrid(1:nx,[1:ny]');
%
%
if ~exist('Qmin','var')
    % to filter circles
    Qmin = nanmean(Q0(:));
    Qstd = nanstd( Q0(:));
end
%
if ~exist('Nstd','var')
    Nstd = 1;
end
%
% $$$ pad = (XX>1.2*r0) & (YY>1.2*r0) &...
% $$$       (YY<ny-1.2*r0) & (XX<nx-1.2*r0);
% $$$ Q1 = Q0.*(Q0>=Qmin & pad);
Q1 = Q0.*(Q0>=Qmin);% only look in regions that are likely to have fronts
% Q0 = Q0.*pad;
% iter = 1;
%
% keep logical array of places checked, and whether fronts/non-fronts
numF = 0*Q0;
yesF = 0*Q0;
nonF = 0*Q0;
%
clear xnext xylog
%
LRflag=0;% if you begin in the middle of the front, must go left or right (when done, take the other fork).
jump2sub=0;% I think that I removed this variable
iter = 0;% how many fronts we've identified.
xylog=[];% keep logs of the (x,y) coords of all fronts
bblog=[];% log of the y vs. x slope of each frontal segment
fnlog=[];% keep track of which contiguous front the xy-points belong to. 
%
% begin search:
% need a while loop, keep track of iterations (loops) here...
loop = 0;
Npts = 1;
while max(Q1(:) - yesF(:).*Q1(:)-nonF(:).*Q1(:))>(Nstd*Qstd) & (loop/Npts<4/r0 | loop<25) & loop<300
    loop=loop+1;% here to prevent a search of every single pixel... this could be better optimized
    % some debuggin code
% $$$     yesF = imfill(yesF,'holes');
% $$$     nonF = imfill(nonF,'holes');
% $$$     if loop == 63
% $$$         break
% $$$     end
%
% first need to initialize stuff,
% 1) start at global maximum front probability,
% 2) if we're at the end of a ridge, but began in the middle, return to the starting point and resume in the oposite direction
% 3) or proceed along current ridge/maximum,
    if  ~exist('xnext','var') & ~LRflag
        % create mask of regions already examined, and regions with data above threshold=Nstd*Qstd (legacy)
        mask = ~(yesF(:) | nonF(:)) & (Q1(:)>Nstd*Qstd);
        [Qmax, istart] = max( mask.*Q1(:));
        % 
        % index of masked global maximum
        x0 = XX(istart);
        y0 = YY(istart);
        newFront=1;
        bb_running = 0;
        iter = iter+1;
    elseif ~exist('xnext','var') & LRflag
        x0 = xyLRnext(1);
        y0 = xyLRnext(2);
        LorR = -LRflag;
        LRflag=0;
        dist = LorR*r0;
        %
        bb0= bb0LR;
        bb_running = bb0(2);
    elseif ~isempty(xnext)
        x0 = xnext;
        y0 = ynext;
    end
    %
    %
    % points on perimeter of circle with radius=r0 centered on maximum
    xp = x0+r0.*cosd([0:360]);
    yp = y0+r0.*sind([0:360]);        
    % logical vector of points within r0
    I   = ( sqrt( (XX(:)-x0).^2 + (YY(:)-y0).^2)<=r0);
    X   = XX(I)-x0;% shift to distance from maximum
    Y   = YY(I)-y0;
    %
    % front probablilities of points within r0
    Q   = Q1(I);
    %
    % if no pixels have probability greater than threshold, Q>Qmin+1*Qstd, then skip,
    % or if we've already found a front in this region, then skip
    if ~any(Q>Qmin)
        % keep log of regions without fronts, but don't overwrite regions with fronts
        nonF(I & ~yesF(:))=1;
        % for debugging
% $$$         disp(['No valid points, clearing vars (x,y)_next; iter=',num2str(loop)])
        % to re-initialize at (1), must clear vars 
        clear xnext ynext
        continue
        % for debugging
% $$$         elseif sum(I & ~(nonF(:) | yesF(:)) & pad(:))/sum(I)<0.5
% $$$         %
% $$$         % just to make sure that we don't get stuck...
% $$$ % $$$             disp('too few valid points in region')
% $$$             yesF(I & ~yesF(:))=1;% was nonF
% $$$             clear xnext ynext
% $$$             continue
    end
    %
    % perform radon transform on probability within r0
    [RTnorm,Rm,Tm] = radon_DG(X,Y,Q,r0,dr,dT);
    % Get maximum:
    % create logical array of points within "threshold" distance of the maximum, including previous fronts
    in = (abs(Rm-X*cos(Tm)-Y*sin(Tm))<threshold & ~yesF(I));
    %
    % what is the variation in variance explained by each (r,theta) in the radon transform
    stdR = std(std(RTnorm));
    % how many valid points are within a threshold distance of the line of maximum variance
    Np   = sum(in);
    %
    if Np*stdR<np_min 
% $$$         disp(['too few points; iter=',num2str(loop)])
        nonF(I & ~yesF(:))=1;
        clear xnext ynext
        continue
    end
    %
    %
    % least-squares fit for the line of maximum variance
    bb0 = [0*X(in)+1 X(in)+x0]\(Y(in)+y0);
    theta = atan(bb0(2));
    %
    % the slope should have some standard limits (not propagating offshore or perfectly alongshore)
    if abs(theta*180/pi)>55 & abs(theta*180/pi)<125
% $$$         disp(['front too steep, skipping iter=',num2str(loop)])
        nonF(I & ~yesF(:)) = 1;
        clear xnext ynext
        continue
    elseif abs(theta-atan(bb_running))*180/pi>60 & abs(theta-atan(bb_running))*180/pi<120
% $$$         disp(['large change in front slope, skipping iter=',num2str(loop)])
        clear xnext ynext
        continue
    end
    %
    % rotate to an along-front coordinate system
    x = X(in); xbar = mean(x);
    y = Y(in); ybar = mean(y);
    % assume predominately horizontal
    G = [cos(theta) sin(theta);...
         -sin(theta) cos(theta)];
    xyp = G*[x(:)'-xbar;y(:)'-ybar];
    xp = xyp(1,:)';
    yp = xyp(2,:)';
    %
    % re-grid to uniform mesh
    [xxs,yys] = meshgrid([min(xp)-1:dr:max(xp)+1],[-np_min:1:np_min]);
    % un-rotate this grid so we don't go beyond image boundaries
    xys = G'*[xxs(:),yys(:)]';
    xs = xys(1,:)'+xbar; 
    ys = xys(2,:)'+ybar;
    % check that mapped points are within the image
    yr = round(ys+y0);
    xr = round(xs+x0);
    try % this will cause an error if mapped points are outside image
        J  = sub2ind(size(Q1),yr,xr);
    catch % this is kludgy, but works
        xr = reshape(xr,size(xxs));
        yr = reshape(yr,size(xxs));
        ip = inpolygon(xr,yr,[1 nx nx 1 1],[1 1 ny ny 1]);
        ip = reshape(ip,size(xxs));
        dum= min(ip,[],1);
        ind= find(dum);
        if isempty(ind)
% $$$             disp('transformed sample points outside domain')        
            nonF(I & ~yesF(:))=1;
            clear xnext ynext            
            continue
        end
        xr = xr(:,ind);
        yr = yr(:,ind);
        xxs=xxs(:,ind);
        yys=yys(:,ind);
        J  = sub2ind(size(Q1),yr(:),xr(:));        
    end
    %
    % Now we have ~1:1 mapping between along-front coords and original image
    Q2 = reshape(I(J).*Q1(J),size(xxs));
    %
    % mask front intensities that are significantly smaller than the local maximum
    Q2(Q2<0.25*max(Q2(:))) = 0;
    % find the across-front pixel coords of the maximum
    [QMAX,rMAX] = max(Q2,[],1);
    cMAX = 1:size(xxs,2);
    cMAX = cMAX(QMAX>0);
    rMAX = rMAX(QMAX>0);
    %
    bb1 = [0*cMAX'+1, cMAX']\rMAX';
    rmsDrMAX = rms(diff(rMAX)+sqrt(-1).*diff(cMAX));
    if rmsDrMAX>2.5 | ~any(Q2(:)>Qmin)% r0/(r0/4)
% $$$         disp('noisy maximum')
        nonF(I & ~yesF(:))=1;
        clear xnext ynext            
        continue
    end
    %
    % indices around maxima to mask
    I2 = reshape(0*I,ny,nx);
    I2(J) = 1;
    I2 = ceil(conv2(I2,ones(3,3)/9,'same'));
    I2 = imfill(I2,'holes');
    I2 = I2(:);
    if plotter
        hold on,plot(ax,YY(I & I2),XX(I & I2),'.c')
    end
    %
    % swap subscripts to indices
    Jmax = sub2ind(size(xxs),rMAX',cMAX');
    %
    % rotate coordinates of maximum back!
    xyr  = G'*[xxs(Jmax),yys(Jmax)]';
    X2log = round(xyr(1,:)'+xbar)+x0;
    Y2log = round(xyr(2,:)'+ybar)+y0;
% $$$     hold on, plot(X2log,Y2log,'.b')
    %
    % recompute the slope/intercept of the maximum
    bb0 = [0*X2log+1 X2log]\Y2log;
    %
    % move search radius r0 to a new (x0,y0) along the maximum
    % if this is a newFront we can go left or right... let's decide:
    if  newFront
        % distance
        dist = sign(mean(X2log)-x0)*sqrt( (mean(X2log)-x0).^2 + (mean(Y2log)-y0).^2);
        % grow region in appropriate direction
        if dist==0
            dist=1;
        end
        LorR = sign(dist);
        newFront=0;
        LRflag=sign(LorR);
        % is new line to the left or right of original?
        x0y0LR = [x0 y0];
        bb0LR  = bb0;
        dum = x0-LRflag*r0*cos(atan(bb0(2)));
        xnext = round(dum);
        ynext = round([1 dum]*bb0);
        xyLRnext = round([xnext, ynext]);
    end
    %
    % update front points:
    if plotter
        hold on,plot(ax,Y2log,X2log,'.r'),
        pause(0.1)
    end
    % keep a log the the front coordinates, slopes, and number of continuous fronts
    xylog = cat(1,xylog, [X2log, Y2log]);
    Npts  = length(xylog);
    % update front linear (slope,intercept):
    bb_running = bb0(2);
    bblog = cat(1,bblog,ones(length(X2log),1)*bb0'); 
    fnlog = cat(1,fnlog,ones(length(X2log),1)*iter);
    yesF(I2 & I) = 1;
    nonF(I2 & I) = 0;
    %
    %
    % now make the move along the fron a distance r0*sqrt(2)/2 using the angle of new curve:
    xnext = round(x0+LorR*r0*cos(atan(bb0(2))));
    ynext = round(y0+LorR*r0*sin(atan(bb0(2))));
    %
end


