clear all
close all
% the steps involved are,
% 1) define camera, grid, network parameters (done below)
% 1.1) (optional: 1=yes/0=no) re-scale the image intensity (gray-scale) to enhance contrast between foam/water
enhance_image = 1;
% 1.2) add to path functions to read video, grid, and camera parameters:
addpath(genpath('../'));
%      located in waveIMG/mfiles/video_processing:
[info, icp, beta0] = define_camera_parameters();
% prepare image (U,V) coordinates for rectification
[U, V] = meshgrid(0:icp.NU-1, 0:icp.NV-1);
% generate grid (X,Y) coords for transformation
X = info.X_min:info.X_res:info.X_max;
Y = info.Y_min:info.Y_res:info.Y_max;
[xx,yy] = meshgrid(X,Y);
%
% 2) get list of all video directories:
%    Top-level RODSEX directory:
rootDIR = '/data0/ShortCrests/IMG/data/RODSEX/';
%    Define location for figures:
figDIR  = '/data0/ShortCrests/IMG/figures/';
%    sub-directories have the format: yyyymmdd_HH (0800--1800 hours)
%    RODSEX was all 2013, use this to get list of sub-dirs
hourDIRs = dir([rootDIR,filesep,'2013*']);
%    sometimes the files are out of order by HH because of leading zero.
yyyymmdd = regexp( {hourDIRs.name}', '(\d+)(?=_)', 'match', 'once' );
HH       = regexp( {hourDIRs.name}', '(?<=_)(\d+)', 'match', 'once' );
dir_date = datenum([cell2mat(yyyymmdd),cell2mat(HH)],'yyyymmddHH');
[dir_date,srt] = sort(dir_date,'ascend');
hourDIRs = hourDIRs(srt);
Nf       = length(hourDIRs);
% 3) variables to preallocate for archiving:
% cross-shore bins for averaging stats
db    = 5; xbins = [75:db:300];
Nx    = length(xbins);
% crest-length bins for pdfs
dl    = 1;
lbins = 2.^[1:dl:10];
Nl    = length(lbins);
P     = nan(Nx,Nl,Nf);% P(x,l,t)--binned pdf of crest length statistics
L     = nan(Nx,Nf);%    L(x,t) -- avg crest length btw 2 & 5 m cross-shore bins
N     = nan(Nx,Nf);%    N(x,t) -- number of crests
mL    = nan(Nx,Nf);%    mL(x,t)-- log10-mean
sL    = nan(Nx,Nf);%    sL(x,t)-- log10-std
%    
%    These quantities can be derived from the above statistics:
%    Psz(l,t)   -- surfzone averaged P
%    Lsz(t)     -- surfzone averaged L
%    Nsz(t)     -- surfzone integrated N
%    mLsz(t)    -- surfzone averaged log10-mean
%    sLsz(t)    -- surfzone averaged log10-std
%
% 4) begin looping over the directories, within each are multiple 5-minute videos
for ii = 1:Nf
    % 5) get a list of all 5-minute videos for this hour
    videoFILEs = dir([rootDIR,filesep,hourDIRs(ii).name,filesep,'*.mp4']);
    Nv         = length(videoFILEs);
    %
    % 6) preallocate temporary variables:
    Ltmp = [];
    Xtmp = [];
    %
    % 7) begin looping over individual video files:
    for jj=1:Nv
        % 8) define the video path and info and frames,
        videoDIR  = videoFILEs(jj).folder;
        videoFILE = videoFILEs(jj).name;
        videoPATH = [videoDIR,filesep,videoFILE];
        % load the current video, but does not rectify, yet.
        vid   = VideoReader(videoPATH);
        vidHz = vid.FrameRate;
        vidDr = vid.Duration;
        % determine frame indeces from the playback speed and sample frequency.
        invRate           = round(vidHz/info.freq);
        videoFrameIndices = 1:invRate:vid.NumFrames;
        numberVideoFrames = length(videoFrameIndices);
        %
        if vid.Height~=size(U,1) | vid.Width~=size(U,2)
            fprintf('\nvideo dimensions: %f x %f , that differ from known camera parameters: \n\t%s\n',vid.Height,vid.Width,videoDIR)
            break
        end
        %
        % 9) begin a loop over the number of frames (less 2)
        for kk=1:numberVideoFrames-2
            %
            % this is where you'd apply tidal correction
            z_tide    = zeros(size(xx));
            % use CIRN toolbox to map (x,y) to (U,V) for later interpolation
            % if you're not correcting for tides/waterlevel variation, this can be done once
            [Uint,Vint]  = getUVfromXYZ(xx,yy, z_tide, icp, beta0);
            % we use a 3-image time-stack... I trained it on 0.5 Hz.
            frameNum = kk;
            frames   = frameNum + [0 1 2];
            % 10) construct time-stack image
            for ll   = 1:3
                % load frame    
                IMGraw  = double(rgb2gray(read(vid,frames(ll))));
                % interpolate to grid points
                IMG(:,:,ll) = interp2(U,V,IMGraw,Uint,Vint, 'linear', nan);
            end
            %
            % 11) (optional) now use Carinni et al to try and separate water/foam peaks (if any)
            if str2num(HH{ii})==12 & kk==1
                plotter=1;
            else
                plotter=0;
            end
            if enhance_image
                [foam_th,foam_pk,ob,opdf] = water_foam_threshold(IMG,plotter);
                %
                f2 = gcf;
                % now re-scale IMG using the water/foam threshold
                IMG0 = IMG;
                IMG  = 255./(1+exp(-3*pi/2*(IMG0-foam_th)/(255-foam_th)));
                H    = hist(IMG(:),ob);
                if plotter
                    hold on,plot(ob,H/numel(IMG),'-k')
                    figname = fprintf([figDIR,filesep,'intensity_pdf_%s%s.pdf'],yymmdd{ii},HH{ii});
                    exportgraphics(f2,figname)
                    close(f2)
                end
                %
                IMG = uint8(IMG);
                %
                % make a figure
                if plotter
                    f1 = figure;
                    f1a1 = subplot(1,2,1);
                    RI = imref2d(size(IMG0));
                    RI.XWorldLimits = [info.X_min info.X_max];
                    RI.YWorldLimits = [info.Y_min info.Y_max];
                    imshow(uint8(IMG),RI)
                    % imagesc(X, Y, IMG)
                    %               
                    % colormap('bone')
                    xlabel(' $x$ [m]', 'interpreter','latex')
                    ylabel(' $y$ [m]', 'interpreter','latex') 
                    axis(f1a1,'equal')
                    set(f1a1,'tickdir','out','ticklabelinterpreter','latex','fontsize',15,'ydir','normal')
                    title(f1a1,"Psuedo-Image");
                    %
                    figure(f1);
                    f1a2 = subplot(1,2,2);
                    RI = imref2d(size(IMG));
                    RI.XWorldLimits = [info.X_min info.X_max];
                    RI.YWorldLimits = [info.Y_min info.Y_max];
                    imshow(IMG,RI)
                    % imagesc(X, Y, IMG)
                    %               
                    % colormap('bone')
                    xlabel(' $x$ [m]', 'interpreter','latex')
                    ylabel(' $y$ [m]', 'interpreter','latex') 
                    axis(f1a2,'equal')
                    set(f1a2,'tickdir','out','ticklabelinterpreter','latex','fontsize',15,'ydir','normal')
                    title(f1a2,"Enhanced Contrast");
                    linkaxes([f1a1 f1a2])
                    figname = fprintf([figDIR,filesep,'enhanced_img_%s%s.pdf'],yymmdd{ii},HH{ii});
                    exportgraphics(f1,figname)
                    close(f1)
                end
                %
            end
            %
            %
            % 12) apply neural network
            dt = 1/info.freq;
            % [pred,prob,xp,yp,tp] = wave_front_from_IMG_CNN(IMG,X,Y,dt,1);
            [pred,prob,xp,yp,tp] = wave_front_from_IMG_UNET(IMG,X,Y,dt,plotter);
            %
            % 13) try to extract coordinates of the high probability ridges in "prob"
            % to be extra confusing I wrote the search function with (row,column)==(x,y)
            % so we must transpose everything for what comes next...
            r0=20;
            Pmax=1;
            Pmin=0.5*Pmax;
            Pnon=0.15*Pmax;
            % you would need to iterate here through prob(Ny,Nx,Nt)
            [crlog,bblog,fnlog] = bore_front_search(prob',info.Ny,info.Nx,r0,Pnon,Pmin,Pmax,0);
            %
            % 14) now switch everything back from (r,c)=(x,y) to (r,c)=(y,x)
            if isempty(crlog),
                disp(['Uh oh, no fronts identified!'])
                return
            end
            C_front = crlog(:,1);% column==y
            R_front = crlog(:,2);% row   ==x
            ind = sub2ind(size(xx),C_front, R_front);
            X_front = xx(ind);
            Y_front = yy(ind);
            % recall row/column are switched
            rcFront = [C_front R_front];
            xyFront = [X_front Y_front];
            %
            if plotter
                f3 = gcf;
                hold on, plot(X_front,Y_front,'r.','markersize',4)
                figname = fprintf([figDIR,filesep,'labeled_img_%s%s.pdf'],yymmdd{ii},HH{ii});
                exportgraphics(f3,figname)
                close(f3)
            end
            %
            %
            % 15) log the current frame time-stack stats
            [front_number, uni] = unique(fnlog);
            for mm = 1:length(front_number)
                idx = find(fnlog==front_number(mm));
                Ltmp = cat(1,Ltmp,range(Y_front(idx)));
                Xtmp = cat(1,Ltmp,mean(X_front(idx)));
            end
        end
        % 16) combine w/ 5-min stats for this hour... this is done above!
    end
    % 17) archive hourly stats
    % loop over cross-shore bin
    for mm = 1:Nx
        logicX = (Xtmp>=xbins(mm)-db/2 & Xtmp<xbins(mm)+db/2)
        idx    = find(logicX);
        % loop over length bins
        for nn=1:Nl
            logicL = (Xtmp>=xbins(mm)-db/2 & Xtmp<xbins(mm)+db/2);
            P(mm,nn,ii) = sum(logicX & logicL);% P(x,l,t)--binned pdf of crest length statistics
        end
        L(mm,ii) = mean(Ltmp(idx));%    L(x,t) -- avg crest length btw 2 & 5 m cross-shore bins
        N(mm,ii) = sum(logicX);%    N(x,t) -- number of crests
        mL(mm,ii)= mean(log10(Ltmp(idx)),'omitnan');%    mL(x,t)-- log10-mean
        sL(mm,ii)= std(log10(Ltmp(idx)),[],'omitnan');%    sL(x,t)-- log10-std
    end
end
save('/data1/ShortCrests/IMG/RODSEX_IMG_FRONT_STATS.mat')