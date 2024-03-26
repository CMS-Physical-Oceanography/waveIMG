function [foam_th,foam_pk,ob,opdf] = water_foam_threshold(IMG,plotter)
%
% USAGE: [foam_th,foam_pk,ob,opdf] = water_foam_threshold(IMG,plotter)
%
% estimate foam threshold to rescale intensities and enhance contrast.
% follows method used by Carini et al 2015
Nb = 100;
[oH,ob] = hist(IMG(IMG~=0),Nb);
%
% estimate pdf and cdf
opdf = oH./sum(oH);
ocdf = cumsum(opdf);
% only look at intensity characteristic of between %1 and %90 of pixels
valid_cdf = (ocdf>0.01 & ocdf<0.90);
%
% mask the pdf, and find the maximum probability
% this assumes that water is the dominant signal (i.e., foam has smaller maximum)
[opk,ipk] = max(opdf.*valid_cdf);
if ob(ipk)>128,
    disp('peak pdf(I) > 50% of range, using I<128: line 17'),
    [opk,ipk] = max(opdf.*valid_cdf.*(ob<=128));
end
% we're now only considering points above maximum (i.e., look for a foam peak)
valid_pdf = (1:Nb>ipk);
%
% maxima/minima for smooth distributions based on the slope/curvature, a la zero-up
dopdf = gradient(opdf);
d2opdf= gradient(dopdf);
%
% look for zero-up crossing above "water" peak to separate "foam" peak
zu = find(sign(dopdf(ipk:end-1))==-1 & sign(dopdf(ipk+1:end))==1); 
if ~isempty(zu)
    disp('trying zero-up crossing for threshold...')
    ot = ipk+zu;
    if length(ot)>1
        % try to find something that splits the data in half (1/4 weight) and has small pdf minimum (3/4 weight)
        [do, iot] = min( abs( ocdf(ot)-0.5 )/4 + opdf(ot)*3/4 );
        ot = ot(iot);
        disp(['multiple minima... using distance to 50%-cdf and lowest pdf: ', num2str(ob(ot))])
    end
else
    %
    % try the Carini et al 2015 method
    disp('using 2nd-Quartile of d^2/dI^2 (pdf), similar to Carini et al., 2015') 
    [d2max,i2max] = max(d2opdf.*(valid_cdf.*valid_pdf) );
    iGTmax = (1:Nb>i2max);
    Q2 = median(d2opdf(iGTmax & valid_cdf & valid_pdf));
    ot = find(d2opdf(iGTmax & valid_cdf & valid_pdf)<=Q2,1,'first') + i2max - 1;
    %
end
%
% if the zero-up crossing masks a significant number of image, default to carini method
if ocdf(ot)<0.30 | ocdf(ot)>0.90
    disp('foam threshold masks either <30% or >90% of image, line 65'),
    disp('using 2nd-Quartile of d^2/dI^2 (pdf), similar to Carini et al., 2015') 
    [d2max,i2max] = max(d2opdf.*(valid_cdf.*valid_pdf) );
    iGTmax = (1:Nb>i2max);
    Q2 = median(d2opdf(iGTmax & valid_cdf & valid_pdf));
    ot = find(d2opdf(iGTmax & valid_cdf & valid_pdf)<=Q2,1,'first') + i2max - 1;
end
%
% sometimes the pdf is unimodal, and ot=empty
if isempty(ot)
    [d2max,i2max] = max(d2opdf.*(valid_cdf.*valid_pdf) );
    disp('using location of maximum curvature.')
    ot = i2max;
end
%
% Foam threshold
foam_th = ob(ot);
%
% 2nd peak
[opk2,ipk2] = max(opdf.*(valid_cdf.*(1:Nb>ot)));
foam_pk= ob(ipk2);
%
% or mean
foam_cm = sum(ob.*opdf.*(1:Nb>ot))./sum(opdf.*(1:Nb>ot));
%
if foam_cm>foam_pk
    fprintf('\n choosing foam center of mass fcm = %f instead of peak fpk=%f\n',foam_cm,foam_pk)
    foam_pk = foam_cm;
end
%
if plotter
% $$$         wrk = pwd;
% $$$         i1s = find(fin=='/',1,'last');
% $$$         i2s = find(fin(i1s+1:end)=='_',1,'first');
% $$$         fout = [wrk,'/../figures/','pdf_',fin(i1s+i2s+ [21:35]),'.png'];
        fig = figure;
        plot(ob,opdf,'-b','linewidth',2)
        hold on,
        yl = ylim;
        plot(foam_th*[1 1],yl,'--r',foam_pk*[1 1],yl,'r:','linewidth',2)
        xlabel('intensity','interpreter','latex','fontsize',16)
        ylabel('pdf','interpreter','latex','fontsize',16)
% $$$         title([fin(i1s+i2s+ [21:28]),'  ',fin(i1s+i2s+ [30:35])])
% $$$         exportgraphics(fig,fout)
% $$$         close(fig)
end
%
end

