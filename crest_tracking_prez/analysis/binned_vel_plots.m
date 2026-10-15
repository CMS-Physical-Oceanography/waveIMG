
% spatial mean velocity plot — 5x5 m binned grid

bin_size = 5; % m (input)

x_edges = min(all_celerity(:,1)) : bin_size : max(all_celerity(:,1)) + bin_size; % def bin edges spanning data domain
y_edges = min(all_celerity(:,2)) : bin_size : max(all_celerity(:,2)) + bin_size;
x_centers = x_edges(1:end-1) + bin_size/2; % bin centers
y_centers = y_edges(1:end-1) + bin_size/2;

xi = discretize(all_celerity(:,1), x_edges); % assign celerity data into bins
yi = discretize(all_celerity(:,2), y_edges);
n_xbins = length(x_centers);
n_ybins = length(y_centers);
vel_grid = nan(n_ybins, n_xbins);

for r = 1:n_ybins
    for c = 1:n_xbins
        mask = xi == c & yi == r;
        if sum(mask) >= 10  % require at least 3 pts per bin to trust the mean
            vel_grid(r, c) = mean(all_celerity(mask, 5));
        end
    end
end

figure; hold on; % plot
h = imagesc(x_centers, y_centers, vel_grid);
set(h, 'AlphaData', ~isnan(vel_grid));  % hide empty bins
colormap(parula);
cb = colorbar;
cb.Label.String = 'Mean Celerity [m/s]';
clim([0 5]);
axis tight;
set(gca, 'YDir', 'normal');
xlabel('Cross-shore (m)');
ylabel('Alongshore (m)');
title('Mean Celerity — 5×5 m bins');
grid minor; box on;

%% binned bathy from c

bin_size = 5; % m
x_edges = min(all_celerity(:,1)) : bin_size : max(all_celerity(:,1)) + bin_size;
y_edges = min(all_celerity(:,2)) : bin_size : max(all_celerity(:,2)) + bin_size;
x_centers = x_edges(1:end-1) + bin_size/2;
y_centers = y_edges(1:end-1) + bin_size/2;
xi = discretize(all_celerity(:,1), x_edges);
yi = discretize(all_celerity(:,2), y_edges);
n_xbins = length(x_centers);
n_ybins = length(y_centers);
vel_grid = nan(n_ybins, n_xbins);

for r = 1:n_ybins
    for c = 1:n_xbins
        mask = xi == c & yi == r;
        if sum(mask) >= 10
            vel_grid(r,c) = mean(all_celerity(mask,5));
        end
    end
end

a = 1; % correction factor to fit celerity-derived depths to bathy survey data, 1 = no effect
g = 9.81;
depth_grid = (vel_grid).^2 ./ (a^2 *g) - .183; % linear theory, .25 is b/c low tide (rel to navd), + for tide that is below 0

figure; hold on % plot bathy
h = imagesc(x_centers, y_centers, depth_grid);
set(h,'AlphaData',~isnan(depth_grid))
colormap(parula)
cb = colorbar; colormap(flipud(colormap))
cb.Label.String = 'Mean Depth [m, NAVD88]';
clim([0 3]); % adjust to expected depth range
axis tight
set(gca,'YDir','normal')
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title('Celerity-Derived Bathymetry - 10/02, 1hr')
grid minor
box on

xlim([86 180]); 
ylim([602 1000])

%% stats from selected spatial-map bins subplots

y_query = 860; % AS location for stat blocks
min_pts = 250;
edges = 0:0.25:5; % histo bin edges

x_targets = [110 125 140 155 170]; % CS block loc, choose

figure
for b = 1:length(x_targets)

    [~, c] = min(abs(x_centers - x_targets(b)));
    [~, r] = min(abs(y_centers - y_query));

    mask = xi == c & yi == r;
    v_bin = all_celerity(mask,5);

    subplot(2,3,b); hold on
    if numel(v_bin) < min_pts
        text(0.5,0.5,sprintf('Insufficient data\n(n=%d)',numel(v_bin)),'Units','normalized','HorizontalAlignment','center');
        axis off
        continue
    end

    h_hist = histogram(v_bin,edges,'Normalization','probability','EdgeColor','none');

    m_mean = mean(v_bin);
    m_median = median(v_bin);
    m_std = std(v_bin);
    
    h_mean = xline(m_mean,'r-','LineWidth',2); % lines for stats
    h_median = xline(m_median,'y--','LineWidth',2);
    h_std = xline(m_mean+m_std,'r:','LineWidth',1);
    xline(m_mean-m_std,'r:','LineWidth',1,'HandleVisibility','off');  
    legend([h_mean h_median h_std], {sprintf('Mean = %.2f m/s',m_mean), sprintf('Median = %.2f m/s',m_median), ...
       sprintf('\\pm1\\sigma = %.2f m/s',m_std)}, 'Location','northeast','FontSize',6.5);

    title(sprintf('Cell Location: (%.0f, %.0f) [m]',x_centers(c),y_centers(r)))
    xlabel('Celerity [m/s]')

    if b==1 || b==4
        ylabel('Probability')
    end
    xlim([u_min u_max])
    grid on
    box on
    ax = gca;
    pos = ax.Position;
    annotation('textbox',[pos(1)+pos(3)-0.1, pos(2), 0.1, 0.05], 'String', sprintf('n = %d', numel(v_bin)), ...
        'EdgeColor','none','HorizontalAlignment','right','VerticalAlignment','bottom', 'FontSize',8, 'FontWeight','bold');
end

% panel 6, spatial mean map w/ selected blocks where stats are taken
subplot(2,3,6); hold on

h = imagesc(x_centers,y_centers,vel_grid);
set(h,'AlphaData',~isnan(vel_grid))
set(gca,'YDir','normal')
axis tight
colormap(parula)
clim([0 5])
xlabel('Cross-shore (m)')
ylabel('Alongshore (m)')
title('Selected Histogram Cells')

for b = 1:length(x_targets)

    [~, c] = min(abs(x_centers - x_targets(b)));
    [~, r] = min(abs(y_centers - y_query));

    rectangle('Position',[x_edges(c),y_edges(r),bin_size,bin_size],'EdgeColor','r','LineWidth',2)
end
sgtitle(sprintf('Celerity Distribution from 5x5[m] Cells around y = %.0f m',y_query))