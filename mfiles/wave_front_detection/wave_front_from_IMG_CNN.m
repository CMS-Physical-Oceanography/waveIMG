function [pred,prob,xp,yp,tp] = wave_front_from_IMG_CNN(IMG,x,y,dt,plotter);
%
% USAGE: [pred,prob,xp,yp,tp] = wave_front_from_IMG_CNN(IMG,x,y,dt,plotter);
% 
% 
if ~exist('plotter','var')
    plotter=0;
end
%
%  Old method loaded "ocean" which was huge and then down sampled it. 
%  Name           Size                       Bytes  Class    
%               (Ny,Nx,Nt)
%  IMG          2051x876x750            10780056000  double              
%  x             1x876                       7008  double              
%  y          2051x1                        16408  double
%
% get input dimensions
[Ny,Nx,Nt] = size(IMG);
t = (1:Nt)*dt;
dx = x(2)-x(1);
dy = y(2)-y(1);
% dt = t(2)-t(1);
%
[xx,yy]    = meshgrid(x,y);
%
CNN    = load('../../mat_data/imgNet_v8.mat');
imgNet = CNN.imgNet;
inSize = imgNet.Layers(1).InputSize;
nNy = inSize(1);
nNx = inSize(2);
nNt = inSize(3);
%
% resize IMG if necessary
if ~all( [Ny,Nx]==[nNy,nNx] )
    IMG0 = imresize(IMG,[nNy nNx]);
    dxp= dx*Nx/nNx; xp = x(1) + dxp*[0:nNx-1] + (range(x)-dxp*(nNx-1))/2;
    dyp= dy*Ny/nNy; yp = y(1) + dyp*[0:nNy-1] + (range(y)-dyp*(nNy-1))/2;
else
    IMG0=IMG;
    xp = x;
    yp = y;
end
%
% presumaby we're doubling the sample rate t(i+1)-t(i-1) = 2*dt;
dtp= 2*dt;
%
% if IMG has more than 3 layers, processes it iteratively three at a time
ii   = 2:2:Nt-1;
inds = 1:length(ii);
% parfor (ind = inds, 12)
for ind = inds
            tt     = ii(ind);
            tp(ind)= t(tt);
            %
            chnk = IMG0(:,:,tt + [-(nNt-1)/2:1:(nNt-1)/2]);
            lbl  = activations(imgNet,chnk,'softmax');
            %
            [~,pred(:,:,ind)]=max(lbl,[],3);
               prob(:,:,ind) =    lbl(:,:,3);
end
% toc    
% end
if plotter
    fig = figure;
    ax1 = subplot(1,2,1);
    imagesc(ax1,x,y,squeeze(IMG(:,:,2))),colormap(ax1,bone)
    caxis(ax1,[0 255]),
    hold on,
    set(ax1,'ydir','normal')
    ylabel(ax1,'$y$','interpreter','latex','fontsize',16)
    xlabel(ax1,'$x$','interpreter','latex','fontsize',16)
    title(ax1,'Input Image')
    ax2 = subplot(1,2,2);
    imagesc(ax2,xp,yp,squeeze(prob(:,:,1))),
    colormap(ax2,bone),
    caxis(ax2,[0.25 1])
    set(ax2,'ydir','normal')
    linkaxes([ax1,ax2],'xy')
    xlabel(ax2,'$x_p$','interpreter','latex','fontsize',16)
    ylabel(ax2,'$y_p$','interpreter','latex','fontsize',16)
    title(ax2,'Front Probability')    
end
%
end

