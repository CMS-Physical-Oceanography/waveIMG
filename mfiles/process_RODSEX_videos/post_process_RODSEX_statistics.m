clear all
close all
load('/data0/ShortCrests/IMG/RODSEX_IMG_FRONT_STATS.mat')
%
% separate time vector to datevec
date_str = [cell2mat(yyyymmdd),cell2mat(HH)];
% note, the time vector jumps... construct the datenum vector
time_img = datenum( date_str ,'yyyymmddHH');
%
%% load wave data
[t,Hs,Tm0,Dm0,mDirSpread,DirPeakSpread,freqSpread,Et,freqs,dirs] = load_26mWR_wave_stats_multimonth(time_img,0);
%
% first, plot L(x,t)
fig = figure;
ax1 = subplot(3,1,2);
imagesc(1:size(L,2),xbins,L,'AlphaData',~isnan(L))
ylabel(ax1,'$x$ [m]','interpreter','latex')
ax1ticks      = get(ax1,'xtick'); nticks = length(ax1ticks);
ax1ticklabels = cellstr([date_str(ax1ticks,5:6),repmat('/',nticks,1),date_str(ax1ticks,7:8),repmat('-',nticks,1),date_str(ax1ticks,9:10)]);
set(ax1,'xticklabels',ax1ticklabels,'tickdir','out','ticklabelinterpreter','latex','ylim',[85 250],'ydir','normal')
ax1.XAxis.FontSize=10;
colormap(ax1,cmocean('thermal')),
cb1 = colorbar;
ylabel(cb1,'$L$ [m]','interpreter','latex')
set(cb1,'tickdir','out')
%
ax2 = subplot(3,1,3);
imagesc(1:size(L,2),xbins,N,'AlphaData',~isnan(N))
ylabel(ax2,'$x$ [m]','interpreter','latex')
set(ax2,'xtick',ax1ticks,'xticklabels',ax1ticklabels,'tickdir','out','ticklabelinterpreter','latex','ylim',[85 250],'ydir','normal')
ax2.XAxis.FontSize=10;
colormap(ax2,cmocean('amp')),
cb2 = colorbar;
ylabel(cb2,'$N$','interpreter','latex')
set(cb2,'tickdir','out')
%
ax3 = subplot(3,1,1);
plot(time_img,Hs,'-k','linewidth',2)

%
%% look at each pdf(L), should be decaying...
%  can we use this to filter videos with poor crest identification?
ii=149
% hold on,
figure, semilogx(lbins,squeeze(P(23,:,ii)))
%
% cross-shore location of long crests:
Pxt = squeeze(sum(P,2,'omitnan'));
xL  = sum(xbins'.*Pxt,1,'omitnan')./sum(Pxt,1,'omitnan'); %sum( xbins'.*L,1,'omitnan')./sum(L,1,'omitnan');
% image times
idx    = find(~isnan(xL));
%
% so, lets see if there's a relationship between tide level and crest length.
[time_tide,zw] = load_FRF_waterlevels(yyyymmdd{idx(1)},yyyymmdd{idx(end)});
% convert from GMT to EDT
time_tide = time_tide-4/24;
%
%
figure, plot(time_tide,zw,'-k',time_img,(xL-mean(xL,'omitnan'))/mean(xL,'omitnan'),'.r')
%
zw_img = interp1(time_tide,zw,time_img(idx));
xL_img = xL(idx)';
[rho,pval] = corr(zw_img,xL_img);
figure, plot(zw_img,xL_img,'*');
%
%
% get wave heights, too