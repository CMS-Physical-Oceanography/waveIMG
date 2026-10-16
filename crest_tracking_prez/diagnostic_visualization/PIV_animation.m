
%% 2-min PIV plots

load('/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main/data/PIV_2min/PVLAB_PIV_SurfaceFlows.mat')

figure
for k = 1:size(u,3)
    clf
    hold on
    imagesc(FRFx(1,:), FRFy(:,1), u(:,:,k))
    xlim([80 200])
    ylim([600 830])
    colormap(cmocean('balance'))
    caxis([-0.25 0.25])
    cb = colorbar;
    cb.Label.String = 'Cross-shore velocity [m/s]';
    xlabel('Cross-shore [m]')
    ylabel('Alongshore [m]')
    title(sprintf('PIV Cross-shore Velocity - %s', datestr(t(k),'yyyy-mm-dd HH:MM:ss')))
    drawnow
    pause(0.1)
end

%