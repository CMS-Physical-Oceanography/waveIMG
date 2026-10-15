
% Crest Width Statistics (ALL processed videos)
all_widths = vertcat(all_crest_widths{:});
all_widths = all_widths( ~isnan(all_widths) & all_widths > 0 & all_widths <= 8);
edges = 0:0.2:8;

figure
histogram(all_widths,edges,'FaceColor','r','EdgeColor','none','Normalization','probability');
hold on

w_mean   = mean(all_widths); 
w_median = median(all_widths);
w_std    = std(all_widths);

hMean = xline(w_mean,'b-','LineWidth',2);
hMed  = xline(w_median,'k--','LineWidth',2);
hStd  = plot(nan,nan,'w');

xlabel('Crest width [m]');
ylabel('Frequency');
title('Distribution of Crest Width', 'FontSize', 15)
grid on
box on
legend([hMean hMed hStd],{sprintf('Mean = %.2f m',w_mean),sprintf('Median = %.2f m',w_median), ...
    sprintf('Std = %.2f m',w_std)},'Location','northeast');
hold off

% Crest Length Statistics (ALL processed videos)
all_lengths = [];
for k = 1:numel(all_crest_summary)
    if isempty(all_crest_summary{k})
        continue
    end
    all_lengths = [all_lengths; [all_crest_summary{k}.length]'];
end
all_lengths = all_lengths( ~isnan(all_lengths) & all_lengths > 0);
edges = 0:1:50; % range for data

figure
histogram(all_lengths,edges,'FaceColor','r','EdgeColor','none','Normalization','probability');
hold on
L_mean   = mean(all_lengths);
L_median = median(all_lengths);
L_std    = std(all_lengths);

hMean = xline(L_mean,'b-','LineWidth',2);
hMed  = xline(L_median,'k--','LineWidth',2);
hStd  = plot(nan,nan,'w');

xlabel('Crest length [m]');
ylabel('Frequency');
title('Distribution of Crest Lengths', FontSize= 15);
xlim([edges(1) edges(end)]);
grid on
box on
legend([hMean hMed hStd],{sprintf('Mean = %.2f m',L_mean),sprintf('Median = %.2f m',L_median),...
     sprintf('Std = %.2f m',L_std)},'Location','northeast');
hold off

%% CS variability - crest length
